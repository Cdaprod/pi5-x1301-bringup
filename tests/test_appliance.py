#!/usr/bin/env python3
"""Hardware-free tests for appliance persistence, discovery, policy, and generation."""
import importlib.util, json, os, subprocess, sys, tempfile, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parents[1] / "tools/x1301"))
from x1301lib import *

def load_script(name):
    spec=importlib.util.spec_from_file_location(name,Path(__file__).parents[1]/"tools/x1301"/f"{name}.py")
    module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module

class ApplianceTests(unittest.TestCase):
    def setUp(self): self.tmp=tempfile.TemporaryDirectory(); self.root=Path(self.tmp.name)
    def tearDown(self): self.tmp.cleanup()
    def test_atomic_json(self):
        p=self.root/"a"/"state.json"; atomic_json(p,{"state":"DISCONNECTED"}); self.assertEqual(read_json(p,{})["state"],"DISCONNECTED"); self.assertFalse(list(p.parent.glob(".*.tmp")))
    def test_states_from_env(self):
        p=self.root/"state.env"; p.write_text("X1301_SIGNAL_STATE='PRESENT_NO_SIGNAL'\nX1301_POWER_PRESENT='1'\n"); self.assertEqual(parse_env(p)["signal_state"],"PRESENT_NO_SIGNAL")
    def test_stable_identity_ignores_nodes(self):
        a={"driver":"rp1-cfe","bridge":"tc358743","media_topology":"graph","video":"/dev/video0"}; b={**a,"video":"/dev/video9"}; self.assertEqual(adapter_id(a),adapter_id(b))
    def test_stable_identity_ignores_alsa_card_number(self):
        cards=parse_arecord_cards("card 2: tc358743 [tc358743], device 0: HDMI Capture [HDMI Capture]")
        moved=parse_arecord_cards("card 7: tc358743 [tc358743], device 0: HDMI Capture [HDMI Capture]")
        self.assertEqual(cards[0]["id"],moved[0]["id"]); self.assertNotEqual(cards[0]["pcm"],moved[0]["pcm"])
    def test_audio_semantic_preference_and_absence(self):
        text="card 0: USB [USB Mic], device 0: USB Audio [USB]\ncard 3: tc358743 [TC358743 HDMI], device 0: HDMI [HDMI]"
        self.assertEqual(parse_arecord_cards(text)[0]["pcm"],"hw:3,0"); self.assertEqual(parse_arecord_cards(""),[])
    def test_cec_fingerprint_excludes_runtime_addresses(self):
        first=parse_cec_source("logical address: 1\nVendor ID: 0x123456\nOSD Name: Nikon Z7\nDevice Type: Playback\n")
        second=parse_cec_source("logical address: 7\nVendor ID: 0x123456\nOSD Name: Nikon Z7\nDevice Type: Playback\n")
        self.assertEqual(first,second); self.assertEqual(cec_fingerprint(first),cec_fingerprint(second))
    def test_adapter_and_source_identity_are_separate(self):
        identity={"driver":"rp1-cfe","bridge":"tc358743","media_topology":"graph"}; aid=adapter_id(identity)
        self.assertEqual(source_id(aid),source_id(aid)); self.assertNotEqual(source_id(aid,"nikon"),source_id(aid,"laptop"))
        self.assertEqual(source_id(aid,"nikon"),source_id(aid,"nikon"))
    def test_source_identity_does_not_depend_on_alsa_availability(self):
        base={"driver":"rp1-cfe","bridge":"tc358743","media_topology":"graph"}
        self.assertEqual(adapter_id(base),adapter_id({**base,"alsa_id":"tc358743"}))
        self.assertEqual(source_id(adapter_id(base),"nikon"),source_id(adapter_id({**base,"alsa_id":"tc358743"}),"nikon"))
    def test_hw_params(self):
        parsed=parse_hw_params("FORMAT: [ S16_LE S24_LE S32_LE ]\nCHANNELS: [2 8]\nRATE: [32000 192000]\n",48000)
        self.assertEqual((parsed["format"],parsed["channels"],parsed["sample_rate"]),("S32_LE",2,48000))
    def test_first_profile_then_recovery(self):
        reg=Registry(self.root/"etc",self.root/"var"); ident={"driver":"rp1-cfe","bridge":"tc358743","media_topology":"g"}
        aid,did,p=reg.recognize(ident,{"video_device":"/dev/video0"}); profile=self.root/"var/profiles.d"/f"{did}.json"; data=read_json(profile,{}); data["alias"]="nikon-z7"; atomic_json(profile,data)
        aid2,did2,p2=reg.recognize(ident,{"video_device":"/dev/video4"}); self.assertEqual((aid,did),(aid2,did2)); self.assertEqual(p2["alias"],"nikon-z7")
    def test_port_persistence(self):
        p=self.root/"ports.json"; first=allocate_ports(p,in_use=lambda _:False); second=allocate_ports(p,in_use=lambda _:True); self.assertEqual(first,second)
    def test_configured_port_persistence(self):
        p=self.root/"ports.json"; first=allocate_ports(p,{"control_http":9000},lambda _:False); second=allocate_ports(p,{"control_http":9000},lambda _:True); self.assertEqual(first,second)
    def test_port_conflict(self):
        record=allocate_ports(self.root/"ports.json",in_use=lambda p:p==8080); self.assertEqual(record["ports"]["control_http"],8081); self.assertEqual(record["port_conflicts"] if "port_conflicts" in record else record["conflicts"][0]["requested"],8080)
    def test_persisted_external_conflict_is_revalidated_at_bootstrap(self):
        path=self.root/"ports.json"; allocate_ports(path,in_use=lambda _:False)
        record=allocate_ports(path,in_use=lambda p:"nginx" if p==8080 else False,validate_persisted=True)
        self.assertEqual(record["ports"]["control_http"],8081); self.assertEqual(record["conflicts"][0]["conflict"],"nginx")
    def test_edid_resolution_and_missing(self):
        d=self.root/"edid"; d.mkdir(); f=d/"x1301-compatible.txt"; f.write_text("00")
        self.assertEqual(resolve_edid("1080p60-safe",[d]),f); self.assertRaises(FileNotFoundError,resolve_edid,"1080p60-safe",[self.root/"missing"])
    def test_capability_probe(self):
        def run(args,**kw): return subprocess.CompletedProcess(args,0," V..... h264_v4l2m2m\n V..... libx264\n" if "-encoders" in args else "","")
        caps=probe_capabilities(run,[]); self.assertFalse(caps["encoders"]["h264_v4l2m2m"]); self.assertTrue(caps["encoders"]["libx264"]); self.assertFalse(caps["encoders"]["h264_vaapi"])
    def test_capability_cache_avoids_reprobe(self):
        calls=[]
        def run(args,**kw): calls.append(tuple(args)); return subprocess.CompletedProcess(args,0,"ffmpeg version test\n","")
        path=self.root/"caps.json"; cached_capabilities(path,run=run); first=len(calls); cached_capabilities(path,run=run)
        self.assertLess(len(calls)-first,first); self.assertFalse(any("-encoders" in call for call in calls[first:]))
    def test_hardware_pipeline_first(self):
        p=select_pipeline({"encoders":{"h264_v4l2m2m":True,"libx264":True}},"quality",1920,60); self.assertEqual(p["encoder_backend"],"hardware"); self.assertFalse(p["degraded"])
    def test_software_guardrail(self):
        p=select_pipeline({"encoders":{"libx264":True}},"quality",3840,60); self.assertEqual((p["target_width"],p["target_fps"]),(1280,30)); self.assertTrue(p["degraded"])
    def test_generated_config(self):
        p=self.root/"generated/mediamtx.yml"; self.assertTrue(generate_mediamtx(p,DEFAULT_PORTS)); stamp=p.stat().st_mtime_ns
        self.assertFalse(generate_mediamtx(p,DEFAULT_PORTS)); self.assertEqual(stamp,p.stat().st_mtime_ns); self.assertIn("paths:\n  x1301:",p.read_text())
    def test_disconnected_to_source_does_not_rewrite_fanout_config(self):
        appliance=load_script("x1301-appliance"); etc=self.root/"etc"; var=self.root/"var"; run=self.root/"run"
        etc.mkdir(); atomic_json(etc/"config.json",{}); atomic_json(var/"capabilities.json",{"schema":2,"encoders":{"libx264":True}})
        appliance.reconcile(etc,var,run); generated=run/"generated/mediamtx.yml"; stamp=generated.stat().st_mtime_ns
        (run/"state.env").write_text("X1301_RP1_CFE_DETECTED='1'\nX1301_DRIVER='rp1-cfe'\nX1301_CONFIGURED='1'\nX1301_WIDTH='1920'\nX1301_HEIGHT='1080'\nX1301_FPS='60'\nX1301_MODE_GENERATION='1'\n")
        appliance.reconcile(etc,var,run); self.assertEqual(stamp,generated.stat().st_mtime_ns)
    def test_stream_uses_validated_encoder_candidates(self):
        stream=load_script("x1301-stream"); old=stream.os.environ.get("X1301_VAR"); stream.os.environ["X1301_VAR"]=str(self.root)
        try:
            atomic_json(self.root/"capabilities.json",{"encoders":{"h264_v4l2m2m":False,"libx264":True,"libopenh264":True}})
            self.assertEqual(stream.encoder_candidates({}),["libx264","libopenh264"])
        finally:
            if old is None: stream.os.environ.pop("X1301_VAR",None)
            else: stream.os.environ["X1301_VAR"]=old
    def test_urls_use_hostname(self): self.assertIn("pi5.local",urls("pi5",DEFAULT_PORTS,"camera")["webrtc"])

if __name__ == "__main__": unittest.main()
