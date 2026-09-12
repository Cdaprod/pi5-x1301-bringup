#!/usr/bin/env python3
"""Hardware-free tests for appliance persistence, discovery, policy, and generation."""
import json, os, subprocess, sys, tempfile, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parents[1] / "tools/x1301"))
from x1301lib import *

class ApplianceTests(unittest.TestCase):
    def setUp(self): self.tmp=tempfile.TemporaryDirectory(); self.root=Path(self.tmp.name)
    def tearDown(self): self.tmp.cleanup()
    def test_atomic_json(self):
        p=self.root/"a"/"state.json"; atomic_json(p,{"state":"DISCONNECTED"}); self.assertEqual(read_json(p,{})["state"],"DISCONNECTED"); self.assertFalse(list(p.parent.glob(".*.tmp")))
    def test_states_from_env(self):
        p=self.root/"state.env"; p.write_text("X1301_SIGNAL_STATE='PRESENT_NO_SIGNAL'\nX1301_POWER_PRESENT='1'\n"); self.assertEqual(parse_env(p)["signal_state"],"PRESENT_NO_SIGNAL")
    def test_stable_identity_ignores_nodes(self):
        a={"driver":"rp1-cfe","bridge":"tc358743","media_topology":"graph","video":"/dev/video0"}; b={**a,"video":"/dev/video9"}; self.assertEqual(source_id(a),source_id(b))
    def test_stable_identity_ignores_alsa_card_number(self):
        cards=parse_arecord_cards("card 2: tc358743 [tc358743], device 0: HDMI Capture [HDMI Capture]")
        moved=parse_arecord_cards("card 7: tc358743 [tc358743], device 0: HDMI Capture [HDMI Capture]")
        self.assertEqual(cards[0]["id"],moved[0]["id"]); self.assertNotEqual(cards[0]["pcm"],moved[0]["pcm"])
    def test_audio_semantic_preference_and_absence(self):
        text="card 0: USB [USB Mic], device 0: USB Audio [USB]\ncard 3: tc358743 [TC358743 HDMI], device 0: HDMI [HDMI]"
        self.assertEqual(parse_arecord_cards(text)[0]["pcm"],"hw:3,0"); self.assertEqual(parse_arecord_cards(""),[])
    def test_hw_params(self): self.assertEqual(parse_hw_params("FORMAT: S32_LE\nCHANNELS: 2\nRATE: 48000\n"),{"channels":2,"format":"S32_LE","sample_rate":48000})
    def test_first_profile_then_recovery(self):
        reg=Registry(self.root/"etc",self.root/"var"); ident={"driver":"rp1-cfe","bridge":"tc358743","media_topology":"g"}
        did,p=reg.recognize(ident,{"video_device":"/dev/video0"}); profile=self.root/"var/profiles.d"/f"{did}.json"; data=read_json(profile,{}); data["alias"]="nikon-z7"; atomic_json(profile,data)
        did2,p2=reg.recognize(ident,{"video_device":"/dev/video4"}); self.assertEqual(did,did2); self.assertEqual(p2["alias"],"nikon-z7")
    def test_port_persistence(self):
        p=self.root/"ports.json"; first=allocate_ports(p,in_use=lambda _:False); second=allocate_ports(p,in_use=lambda _:True); self.assertEqual(first,second)
    def test_configured_port_persistence(self):
        p=self.root/"ports.json"; first=allocate_ports(p,{"control_http":9000},lambda _:False); second=allocate_ports(p,{"control_http":9000},lambda _:True); self.assertEqual(first,second)
    def test_port_conflict(self):
        record=allocate_ports(self.root/"ports.json",in_use=lambda p:p==8080); self.assertEqual(record["ports"]["control_http"],8081); self.assertEqual(record["port_conflicts"] if "port_conflicts" in record else record["conflicts"][0]["requested"],8080)
    def test_edid_resolution_and_missing(self):
        d=self.root/"edid"; d.mkdir(); f=d/"x1301-compatible.txt"; f.write_text("00")
        self.assertEqual(resolve_edid("1080p60-safe",[d]),f); self.assertRaises(FileNotFoundError,resolve_edid,"1080p60-safe",[self.root/"missing"])
    def test_capability_probe(self):
        def run(args,**kw): return subprocess.CompletedProcess(args,0," V..... h264_v4l2m2m\n V..... libx264\n" if "-encoders" in args else "","")
        caps=probe_capabilities(run); self.assertTrue(caps["encoders"]["h264_v4l2m2m"]); self.assertFalse(caps["encoders"]["h264_vaapi"])
    def test_hardware_pipeline_first(self):
        p=select_pipeline({"encoders":{"h264_v4l2m2m":True,"libx264":True}},"quality",1920,60); self.assertEqual(p["encoder_backend"],"hardware"); self.assertFalse(p["degraded"])
    def test_software_guardrail(self):
        p=select_pipeline({"encoders":{"libx264":True}},"quality",3840,60); self.assertEqual((p["target_width"],p["target_fps"]),(1280,30)); self.assertTrue(p["degraded"])
    def test_generated_config(self):
        p=self.root/"generated/mediamtx.yml"; generate_mediamtx(p,DEFAULT_PORTS,"x1301-test"); text=p.read_text(); self.assertIn("GENERATED",text); self.assertIn("x1301-test",text); self.assertIn("8889",text)
    def test_urls_use_hostname(self): self.assertIn("pi5.local",urls("pi5",DEFAULT_PORTS,"camera")["webrtc"])

if __name__ == "__main__": unittest.main()
