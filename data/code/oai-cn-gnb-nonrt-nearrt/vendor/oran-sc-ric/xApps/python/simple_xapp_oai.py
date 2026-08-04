#!/usr/bin/env python3
"""xApp KPM Style 4 para gNB OAI (S-NSSAI matching + decode E2SM v2.03)."""

import argparse
import datetime
import signal
import threading
import time
from lib.xAppBase import xAppBase


class OaiKpmXapp(xAppBase):
    UNITS = {
        "DRB.UEThpDl": "kbps",
        "DRB.UEThpUl": "kbps",
        "DRB.PdcpSduVolumeDL": "Mb",
        "DRB.PdcpSduVolumeUL": "Mb",
        "DRB.RlcSduDelayDl": "us",
        "RRU.PrbTotDl": "%",
        "RRU.PrbTotUl": "%",
    }

    def __init__(self, http_server_port, rmr_port, unsubscribe_on_exit=False,
                 first_indication_timeout=15, heartbeat_interval=30):
        super(OaiKpmXapp, self).__init__('', http_server_port, rmr_port)
        self.unsubscribe_on_exit = unsubscribe_on_exit
        self.first_indication_timeout = first_indication_timeout
        self.heartbeat_interval = heartbeat_interval
        self.started_at = time.time()
        self.last_indication_at = None
        self.indication_count = 0

    def _format_kpm_time(self, raw_time, decoded_time):
        raw = raw_time.hex() if isinstance(raw_time, (bytes, bytearray)) else str(raw_time)
        if decoded_time in (None, 'n/a'):
            return raw, 'n/a'
        try:
            decoded_dt = datetime.datetime.strptime(decoded_time, '%Y-%m-%d %H:%M:%S UTC')
            now = datetime.datetime.utcnow()
            if abs((decoded_dt - now).total_seconds()) > 86400:
                decoded_time = '{} (fora da janela local; use receivedAt)'.format(decoded_time)
        except Exception:
            pass
        return raw, decoded_time

    def signal_handler(self, sig, frame):
        if not self.unsubscribe_on_exit:
            print("\nEncerrando sem RIC Subscription Delete para preservar o gNB OAI.")
            print("Use --unsubscribe-on-exit apenas para testar o fluxo de delete subscription.")
            self.my_subscriptions.clear()
        self.stop()

    def _watchdog(self):
        next_heartbeat = self.first_indication_timeout
        while self.running:
            time.sleep(1)
            elapsed = int(time.time() - self.started_at)
            if self.indication_count == 0 and elapsed >= next_heartbeat:
                print("")
                print("AVISO: subscription ativa, mas nenhuma RIC Indication recebida após {}s.".format(elapsed))
                print("       Verifique tráfego UE->DN, PDU session, RNIB/E2 e processos gNB/UE duplicados.")
                print("       Comandos úteis:")
                print("         ./scripts/test_oran_ric.sh")
                print("         ./scripts/observe_oai_radio_kpis.sh")
                print("         ip -brief addr show oaitun_ue1")
                next_heartbeat += self.heartbeat_interval
            elif self.indication_count > 0 and self.heartbeat_interval > 0 and elapsed >= next_heartbeat:
                age = int(time.time() - self.last_indication_at) if self.last_indication_at else elapsed
                print("Heartbeat xApp: indications={}, última há {}s".format(self.indication_count, age))
                next_heartbeat += self.heartbeat_interval

    def my_subscription_callback(self, e2_agent_id, subscription_id, indication_hdr, indication_msg):
        self.indication_count += 1
        self.last_indication_at = time.time()
        raw_time = indication_hdr.get('colletStartTime')
        indication_hdr = self.e2sm_kpm.extract_hdr_info(indication_hdr)
        meas_data = self.e2sm_kpm.extract_meas_data(indication_msg)
        received_at = datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')
        raw_time, decoded_time = self._format_kpm_time(raw_time, indication_hdr.get('colletStartTime', 'n/a'))

        print("\nRIC Indication from {} (sub {})".format(e2_agent_id, subscription_id))
        print("  receivedAt:", received_at)
        print("  kpmTimeRaw:", raw_time)
        print("  kpmTimeDecoded:", decoded_time)
        for ue_id, ue_meas_data in meas_data.get("ueMeasData", {}).items():
            print("  UE_id:", ue_id)
            granul = ue_meas_data.get("granulPeriod")
            if granul is not None:
                print("    granulPeriod:", granul)
            for metric_name, values in ue_meas_data.get("measData", {}).items():
                nums = [v for v in (values or []) if v is not None]
                total = sum(nums) if nums else 0.0
                unit = self.UNITS.get(metric_name)
                if unit:
                    if metric_name.startswith("RRU.PrbTot") and total > 100:
                        print("    {}: {:.3f} {} (fora da faixa 0-100; normalizado=100.000 %)".format(
                            metric_name, total, unit))
                    else:
                        print("    {}: {:.3f} {}".format(metric_name, total, unit))
                else:
                    print("    {}: {:.3f}".format(metric_name, total))

    @xAppBase.start_function
    def start(self, e2_node_id, metric_names, sst, sd):
        report_period = 1000
        granul_period = 1000
        print("Subscribe OAI KPM Style 4: node={}, metrics={}, S-NSSAI={}/{}".format(
            e2_node_id, metric_names, sst, sd))
        self.e2sm_kpm.subscribe_report_service_style_4_oai(
            e2_node_id, report_period, metric_names, granul_period,
            self.my_subscription_callback, sst=sst, sd=sd)
        threading.Thread(target=self._watchdog, daemon=True).start()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='KPM xApp for OAI gNB (O-RAN SC nearRT)')
    parser.add_argument("--http_server_port", type=int, default=8093)
    parser.add_argument("--rmr_port", type=int, default=4562)
    parser.add_argument("--e2_node_id", type=str, default='gnb_208_095_00000e00')
    parser.add_argument("--ran_func_id", type=int, default=2)
    parser.add_argument("--metrics", type=str, default='DRB.UEThpDl,DRB.UEThpUl')
    parser.add_argument("--sst", type=int, default=222, help="S-NSSAI SST (gnb.conf)")
    parser.add_argument("--sd", type=int, default=123, help="S-NSSAI SD (gnb.conf)")
    parser.add_argument("--unsubscribe-on-exit", action="store_true",
                        help="Envia RIC Subscription Delete ao sair. No gNB OAI deste lab pode abortar o nr-softmodem.")
    parser.add_argument("--first-indication-timeout", type=int, default=15,
                        help="Tempo para avisar se a subscription não gerar RIC Indication.")
    parser.add_argument("--heartbeat-interval", type=int, default=30,
                        help="Intervalo de heartbeat/novo aviso em segundos; 0 reduz mensagens.")
    args = parser.parse_args()

    xapp = OaiKpmXapp(args.http_server_port, args.rmr_port, args.unsubscribe_on_exit,
                      args.first_indication_timeout, args.heartbeat_interval)
    xapp.e2sm_kpm.set_ran_func_id(args.ran_func_id)

    signal.signal(signal.SIGQUIT, xapp.signal_handler)
    signal.signal(signal.SIGTERM, xapp.signal_handler)
    signal.signal(signal.SIGINT, xapp.signal_handler)

    xapp.start(args.e2_node_id, args.metrics.split(","), args.sst, args.sd)
