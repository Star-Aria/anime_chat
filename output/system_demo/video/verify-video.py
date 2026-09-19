"""Decode every exported frame and measure continuity of the expected moving regions."""
from pathlib import Path
import json
import cv2
import numpy as np

ROOT=Path(__file__).resolve().parent.parent
VIDEO=ROOT/'brain-medical-system-demo-v4.mp4'
QA=ROOT/'video'/'qa-v4'
cap=cv2.VideoCapture(str(VIDEO))
if not cap.isOpened():
    raise RuntimeError(f'Cannot decode {VIDEO}')
fps=cap.get(cv2.CAP_PROP_FPS)
expected=int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
width=int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
height=int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
previous=None
count=0
black=[]
frozen=[]
mean_deltas=[]
brain_deltas=[]
header_deltas=[]
eeg_deltas=[]
selected={int(t*fps):t for t in [0,2.2,3.8,6.5,9.2,11.9,13.8,14.3,15.0,17.8]}
while True:
    ok,frame=cap.read()
    if not ok:
        break
    gray=cv2.cvtColor(frame,cv2.COLOR_BGR2GRAY)
    if gray.mean()<5:
        black.append(count)
    if count in selected:
        cv2.imwrite(str(QA/f'encoded-{selected[count]:04.1f}s.jpg'),frame,[cv2.IMWRITE_JPEG_QUALITY,95])
    if previous is not None:
        delta=cv2.absdiff(gray,previous)
        mean_deltas.append(float(delta.mean()))
        brain_deltas.append(float(delta[320:870,510:1260].mean()))
        eeg_deltas.append(float(delta[703:766,116:336].mean()))
        header_deltas.append(float(delta[0:64,:].mean()))
        if not np.any(delta):
            frozen.append(count)
    previous=gray
    count+=1
cap.release()
summary={
    'file':str(VIDEO),'resolution':[width,height],'fps':fps,
    'metadata_frame_count':expected,'decoded_frames':count,'duration_seconds':count/fps,
    'black_frames':black,'identical_consecutive_frames':frozen,
    'mean_frame_difference':float(np.mean(mean_deltas)),
    'mean_brain_region_difference':float(np.mean(brain_deltas)),
    'mean_eeg_region_difference':float(np.mean(eeg_deltas)),
    'mean_static_header_difference':float(np.mean(header_deltas)),
    'bytes':VIDEO.stat().st_size,
    'checks_passed':count==1080 and expected==1080 and fps==60 and width==1920 and height==1080 and not black and not frozen,
}
(QA/'video-validation.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
print(json.dumps(summary,indent=2))
if not summary['checks_passed']:
    raise RuntimeError('Export validation failed')
