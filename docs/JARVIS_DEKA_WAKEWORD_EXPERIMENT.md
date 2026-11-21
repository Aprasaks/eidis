# DEKA wakeword experiment
- User selected Korean "데카" as call word; production JARVIS name and code unchanged.
- Local openWakeWord feature classifier and separate whole-utterance template comparison. 64 synthetic training clips/templates, 1864 classifier frames. Two held-out voices, rates 155/210; 8 calls, 80 noncalls including unseen phrases.
- At 0.5 threshold, ONNX 8/8 calls, 9/80 false alarms; template 4/8 calls, 5/80 false alarms. Not sufficient for always-on deployment. No real-world FAR measurement.
- START_JARVIS_DEKA_TEST.command runs 8 guided personal tests, no training, no storage, no automatic activation, explicit YES and Enter for each 3-second capture. Use the score and expected label to distinguish misses and false calls. Model and reports outside git.
- Existing JARVIS unaffected; no background capture. Only consider activation after real-speech and false-alarm trials, and exclusive microphone handoff.
