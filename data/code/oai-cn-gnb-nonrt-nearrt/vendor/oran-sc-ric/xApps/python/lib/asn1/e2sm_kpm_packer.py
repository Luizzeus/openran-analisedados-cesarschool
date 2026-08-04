import os
import asn1tools

class e2sm_kpm_packer(object):
    def __init__(self):
        super(e2sm_kpm_packer, self).__init__()
        self.my_dir = os.path.dirname(os.path.abspath(__file__))
        asn1_files = [self.my_dir+'/e2sm-v5.00.asn', self.my_dir+'/e2sm-kpm-v4.00.asn']
        self.asn1_compiler = asn1tools.compile_files(asn1_files,'per')
        v203_asn = self.my_dir + '/e2sm-kpm-v2.03.asn'
        self.asn1_compiler_v203 = None
        if os.path.isfile(v203_asn):
            self.asn1_compiler_v203 = asn1tools.compile_files(
                [self.my_dir + '/e2sm-v5.00.asn', v203_asn], 'per')

    def pack_event_trigger_def(self, reportingPeriod):
        e2sm_kpm_trigger_def = {'eventDefinition-formats': ('eventDefinition-Format1', {'reportingPeriod': reportingPeriod})}
        e2sm_kpm_trigger_def = self.asn1_compiler.encode('E2SM-KPM-EventTriggerDefinition', e2sm_kpm_trigger_def)
        return e2sm_kpm_trigger_def

    def _pack_meas_info_list(self, metric_names):
        measInfoList = []
        # TODO: pack also labels
        for metric_name in metric_names:
            metric_def = {'measType': ('measName', metric_name), 'labelInfoList': [{'measLabel': {'noLabel': 'true'}}]}
            measInfoList.append(metric_def)
        return measInfoList

    def _pack_ue_id_list(self, ue_ids):
        matchingUEidList = []
        for ue_id in ue_ids:
            matchingUEidList.append({'ueID': ('gNB-DU-UEID', {'gNB-CU-UE-F1AP-ID': ue_id})})
        return matchingUEidList

    def _pack_matching_conds_list(self, matchingConds):
        matchingCondList = matchingConds
        return matchingCondList

    def _pack_matching_ue_conds_list(self, matchingUeConds):
        matchingUeCondList = matchingUeConds
        return matchingUeCondList

    def pack_action_def_format1(self, metric_names, granulPeriod=100):
        if not isinstance(metric_names, list):
            metric_names = [metric_names]

        measInfoList = self._pack_meas_info_list(metric_names)

        action_def = {'ric-Style-Type': 1,
                      'actionDefinition-formats': ('actionDefinition-Format1', {
                          'measInfoList': measInfoList, 
                          'granulPeriod': granulPeriod
                          })
                     }
        action_def = self.asn1_compiler.encode('E2SM-KPM-ActionDefinition', action_def)
        return action_def

    def pack_action_def_format2(self, ue_id, metric_names, granulPeriod=100):
        if not isinstance(metric_names, list):
            metric_names = [metric_names]

        ue_id = self._pack_ue_id_list([ue_id])
        ue_id = tuple(ue_id[0]['ueID']) # extract as there is only 1 UE

        measInfoList = self._pack_meas_info_list(metric_names)
        action_def = {'ric-Style-Type': 2,
                      'actionDefinition-formats': ('actionDefinition-Format2', {
                          'ueID': ue_id,
                          'subscriptInfo': {
                              'measInfoList': measInfoList, 
                              'granulPeriod': granulPeriod}
                       })
                     }
        action_def = self.asn1_compiler.encode('E2SM-KPM-ActionDefinition', action_def)
        return action_def

    def pack_action_def_format3(self, matchingConds, metric_names, granulPeriod=100):
        if not isinstance(metric_names, list):
            metric_names = [metric_names]

        if (len(metric_names) > 1):
            print("Currently only 1 metric can be requested in E2SM-KPM Report Style 3")
            exit(1)

        matchingCondList = self._pack_matching_conds_list(matchingConds)

        action_def = {'ric-Style-Type': 3, 
                      'actionDefinition-formats': ('actionDefinition-Format3', {
                        'measCondList': [
                          {'measType': ('measName', metric_names[0]), 'matchingCond': matchingCondList}
                        ], 
                      'granulPeriod': granulPeriod})
                     }
        action_def = self.asn1_compiler.encode('E2SM-KPM-ActionDefinition', action_def)
        return action_def

    def pack_action_def_format4(self, matchingUeConds, metric_names, granulPeriod=100):
        if not isinstance(metric_names, list):
            metric_names = [metric_names]

        measInfoList = self._pack_meas_info_list(metric_names)
        matchingUeCondList = self._pack_matching_ue_conds_list(matchingUeConds)

        action_def = {'ric-Style-Type': 4, 
                      'actionDefinition-formats': ('actionDefinition-Format4', 
                        {'matchingUeCondList': matchingUeCondList,
                        'subscriptionInfo': {
                            'measInfoList': measInfoList, 
                            'granulPeriod': granulPeriod
                        }}
                     )}
        action_def = self.asn1_compiler.encode('E2SM-KPM-ActionDefinition', action_def)
        return action_def

    def pack_action_def_format5(self, ue_ids, metric_names, granulPeriod=100):
        if not isinstance(metric_names, list):
            metric_names = [metric_names]

        matchingUEidList = self._pack_ue_id_list(ue_ids)
        measInfoList = self._pack_meas_info_list(metric_names)

        action_def = {'ric-Style-Type': 5,
                       'actionDefinition-formats': ('actionDefinition-Format5', 
                        {'matchingUEidList': matchingUEidList,
                        'subscriptionInfo': {
                            'measInfoList': measInfoList,
                            'granulPeriod': granulPeriod}
                        })
                     }
        action_def = self.asn1_compiler.encode('E2SM-KPM-ActionDefinition', action_def)
        return action_def

    def _decode_with_compilers(self, type_name, msg_bytes, prefer_v203=False):
        compilers = []
        if prefer_v203 and self.asn1_compiler_v203 is not None:
            compilers.append(self.asn1_compiler_v203)
        compilers.append(self.asn1_compiler)
        if not prefer_v203 and self.asn1_compiler_v203 is not None:
            compilers.append(self.asn1_compiler_v203)
        last_err = None
        for compiler in compilers:
            try:
                return compiler.decode(type_name, msg_bytes)
            except Exception as exc:
                last_err = exc
        if last_err is not None:
            raise last_err
        raise ValueError("no ASN.1 compiler available for {}".format(type_name))

    def unpack_indication_header_format1(self, msg_bytes):
        return self._decode_with_compilers('E2SM-KPM-IndicationHeader-Format1', msg_bytes)

    def unpack_indication_header(self, msg_bytes):
        # OAI E2SM-KPM v2.03: senderName pode conter '_' (ngran_gNB) — inválido no PrintableString
        # estrito do asn1tools. Tentamos CHOICE completo, Format1 direto; fallback mínimo.
        attempts = (
            ('E2SM-KPM-IndicationHeader',
             lambda decoded: decoded['indicationHeader-formats'][1]),
            ('E2SM-KPM-IndicationHeader-Format1', lambda decoded: decoded),
        )
        for asn_type, extract in attempts:
            try:
                decoded = self._decode_with_compilers(asn_type, msg_bytes, prefer_v203=True)
                return extract(decoded)
            except Exception:
                continue
        # Fallback: só os primeiros 4 bytes (TimeStamp v2.03), nunca 8 (desalinha PER)
        if len(msg_bytes) >= 4:
            return {'colletStartTime': msg_bytes[:4]}
        return {'colletStartTime': b'\x00\x00\x00\x00'}

    def unpack_indication_message(self, msg_bytes):
        # OAI gNB usa E2SM-KPM v2.03; decoder v4 pode "decodificar" com valores 0.
        return self._decode_with_compilers('E2SM-KPM-IndicationMessage', msg_bytes, prefer_v203=True)
