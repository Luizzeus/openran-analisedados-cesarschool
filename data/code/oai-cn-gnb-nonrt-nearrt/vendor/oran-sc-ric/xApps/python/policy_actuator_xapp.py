#!/usr/bin/env python3
"""xApp consumidor de policy A1 / intent local → E2SM-RC QoS mapping (action=2).

Modo seguro para o gNB OAI deste lab: NUNCA envia PRB quota (action 6).
"""

import argparse
import json
import os
import signal
import time
from datetime import datetime
from pathlib import Path

from lib.xAppBase import xAppBase


class PolicyActuatorXapp(xAppBase):
    def __init__(self, http_server_port, rmr_port):
        super(PolicyActuatorXapp, self).__init__('', http_server_port, rmr_port)
        self.running = True

    def signal_handler(self, sig, frame):
        print("Encerrando policy_actuator_xapp...")
        self.running = False
        self.stop()

    def _load_intent(self, path):
        p = Path(path)
        if not p.is_file():
            return None
        with p.open(encoding="utf-8") as stream:
            return json.load(stream)

    def _apply_intent(self, e2_node_id, intent, audit_path=None):
        action_id = int(intent.get("control_action_id", 2))
        if action_id != 2:
            raise RuntimeError(
                "recusado: apenas control_action_id=2 é seguro no gNB OAI (recebido {})".format(
                    action_id
                )
            )
        ue_id = int(intent.get("ue_id", 1))
        drb_id = int(intent.get("drb_id", 1))
        qfi = int(intent.get("qfi", 1))
        direction = int(intent.get("dir", 0))
        ran_func_id = int(intent.get("ran_func_id", 3))
        self.e2sm_rc.set_ran_func_id(ran_func_id)
        print(
            "{} CONTROL RC style=1 action=2 node={} ue={} drb={} qfi={} dir={}".format(
                datetime.utcnow().strftime("%H:%M:%S"),
                e2_node_id,
                ue_id,
                drb_id,
                qfi,
                direction,
            )
        )
        result = self.e2sm_rc.control_qos_flow_mapping(
            e2_node_id, ue_id, drb_id=drb_id, qfi=qfi, direction=direction, ack_request=1
        )
        if audit_path:
            record = {
                "ts": datetime.utcnow().isoformat() + "Z",
                "event": "real_control_sent",
                **result,
            }
            path = Path(audit_path)
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open("a", encoding="utf-8") as stream:
                stream.write(json.dumps(record, sort_keys=True) + "\n")
        return result

    @xAppBase.start_function
    def start(self, e2_node_id, intent_path, audit_path, once, poll_sec):
        print(
            "Policy actuator xApp: node={} intent={} once={}".format(
                e2_node_id, intent_path, once
            )
        )
        while self.running:
            intent = self._load_intent(intent_path)
            if intent:
                try:
                    self._apply_intent(e2_node_id, intent, audit_path=audit_path)
                    # consome intent para não reenviar em loop
                    try:
                        Path(intent_path).unlink()
                    except OSError:
                        pass
                    if once:
                        break
                except Exception as exc:
                    print("ERRO ao aplicar intent: {}".format(exc))
                    if once:
                        raise
            elif once:
                raise RuntimeError("intent ausente: {}".format(intent_path))
            time.sleep(poll_sec)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--http_server_port", type=int, default=8095)
    parser.add_argument("--rmr_port", type=int, default=4564)
    parser.add_argument("--e2_node_id", type=str, default="gnb_208_095_00000e00")
    parser.add_argument(
        "--intent",
        type=str,
        default=os.environ.get("CLOSED_LOOP_INTENT", "/tmp/oai-closed-loop/pending_rc_control.json"),
    )
    parser.add_argument("--audit", type=str, default="")
    parser.add_argument("--once", action="store_true", help="processa um intent e sai")
    parser.add_argument("--poll-sec", type=float, default=2.0)
    args = parser.parse_args()

    xapp = PolicyActuatorXapp(args.http_server_port, args.rmr_port)
    signal.signal(signal.SIGQUIT, xapp.signal_handler)
    signal.signal(signal.SIGTERM, xapp.signal_handler)
    signal.signal(signal.SIGINT, xapp.signal_handler)
    xapp.start(args.e2_node_id, args.intent, args.audit or None, args.once, args.poll_sec)
