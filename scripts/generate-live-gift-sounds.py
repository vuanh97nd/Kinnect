"""Original short procedural gift cues; no downloaded/licensed music or samples."""
from pathlib import Path
import math,wave,struct,random
root=Path(__file__).resolve().parents[1]/'android/app/src/main/assets/gifts';root.mkdir(exist_ok=True)
notes={'rose':[523.25,659.25,783.99],'star':[783.99,1046.5,1318.51,1567.98],'crown':[392,523.25,659.25,1046.5],'aurora':[440,554.37,659.25,880,1108.73],'meteor':[1318.51,987.77,659.25],'butterfly':[880,1174.66,1046.5,1396.91],'lotus':[523.25,783.99,1046.5,1567.98]}
notes.update({'car':[110,146.83,220],'yacht':[392,587.33,783.99],'castle':[523.25,659.25,783.99,1046.5]})
rate=22050
for name,pitches in notes.items():
 rng=random.Random(name);duration=1.35 if name in ('aurora','lotus')else 1.08;data=[]
 for i in range(int(rate*duration)):
  t=i/rate;sample=0
  for n,freq in enumerate(pitches):
   age=t-n*.10
   if age<0:continue
   envelope=min(1,age/.012)*math.exp(-age*5.3)
   sample+=envelope*(math.sin(2*math.pi*freq*age)+.18*math.sin(2*math.pi*freq*2.01*age))/len(pitches)
  if name=='meteor':sample+=.08*rng.uniform(-1,1)*math.sin(math.pi*min(1,t/.65))*math.exp(-t*6)
  if name=='car':sample=.25*math.sin(2*math.pi*(72*t+88*t*t))*(min(1,t/.06))*math.exp(-t*2)+.04*rng.uniform(-1,1)*math.exp(-t*4)
  if name=='yacht':sample+=.035*rng.uniform(-1,1)*math.sin(math.pi*min(1,t/duration))
  sample*=min(1,(duration-t)/.08);data.append(sample)
 peak=max(abs(v)for v in data)or 1
 with wave.open(str(root/(name+'.wav')),'wb')as f:f.setparams((1,2,rate,0,'NONE','not compressed'));f.writeframes(b''.join(struct.pack('<h',int(v/peak*18000))for v in data))
print('Generated10 original gift sound cues')
