// Kinnect Studio: camera trực tiếp + bộ lọc màu, làm mịn da và sticker bám khuôn mặt.
// Dùng chung cho quay video ngắn và livestream. Camera chỉ bật khi người dùng mở Studio/Live
// và luôn được tắt khi đóng.

export const FILTERS = [
  ["none", "Gốc", "none"],
  ["clear", "Trong trẻo", "contrast(1.08) saturate(1.08) brightness(1.05)"],
  ["milk", "Sữa", "saturate(0.75) brightness(1.08) contrast(0.92) sepia(0.06)"],
  ["peach", "Hồng đào", "saturate(1.05) sepia(0.12) hue-rotate(-12deg) brightness(1.05)"],
  ["warm", "Ấm áp", "saturate(1.15) sepia(0.18) brightness(1.04)"],
  ["cool", "Mát lạnh", "saturate(0.95) hue-rotate(-12deg) brightness(1.03)"],
  ["film", "Phim cũ", "sepia(0.35) saturate(0.75) contrast(0.92) brightness(1.06)"],
  ["mono", "Đen trắng", "grayscale(1) contrast(1.05)"],
  ["noir", "Tương phản", "grayscale(1) contrast(1.4)"],
  ["vivid", "Rực rỡ", "saturate(1.55) contrast(1.08)"],
  ["sunset", "Hoàng hôn", "sepia(0.3) saturate(1.3) hue-rotate(-18deg) brightness(1.04)"],
  ["candy", "Kẹo ngọt", "saturate(1.3) hue-rotate(-8deg) brightness(1.08) contrast(0.95)"],
  ["mint", "Bạc hà", "hue-rotate(14deg) saturate(0.9) brightness(1.06)"],
  ["dream", "Mộng mơ", "saturate(0.85) brightness(1.1) contrast(0.9) hue-rotate(8deg)"],
  ["retro", "Retro", "sepia(0.25) contrast(1.1) saturate(0.9) hue-rotate(-6deg)"],
  ["city", "Thành phố", "saturate(0.7) contrast(1.15) brightness(0.98)"],
  ["cinema", "Cinema", "contrast(1.15) saturate(0.82) sepia(0.12)"],
  ["rose", "Rose", "brightness(1.08) saturate(1.12) sepia(0.16) hue-rotate(320deg)"],
  ["golden", "Golden", "sepia(0.25) saturate(1.2) brightness(1.08)"],
  ["ice", "Ice", "saturate(0.75) hue-rotate(12deg) brightness(1.1)"],
  ["lavender", "Lavender", "hue-rotate(18deg) saturate(0.8) brightness(1.1)"],
  ["choco", "Choco", "sepia(0.4) contrast(1.1) saturate(0.72)"],
  ["polaroid", "Polaroid", "sepia(0.18) contrast(0.9) brightness(1.12) saturate(0.8)"],
  ["teal", "Teal", "hue-rotate(12deg) contrast(1.12) saturate(1.16)"],
];
export const STICKERS = [
  ["none", "Gốc", "○"], ["glasses", "Kính đen", "🕶️"],
  ["round_glasses", "Kính tròn", "👓"], ["heart_glasses", "Kính tim", "💗"], ["neon_glasses", "Kính neon", "⚡"],
  ["hearts", "Tim bay", "💕"], ["crown", "Vương miện", "👑"], ["cat", "Mèo", "🐱"],
  ["bunny", "Thỏ", "🐰"], ["dog", "Cún", "🐶"], ["flowers", "Hoa", "🌸"], ["bow", "Nơ", "🎀"],
  ["sparkle", "Lấp lánh", "✨"], ["stars", "Sao", "⭐"], ["butterfly", "Bướm", "🦋"],
  ["halo", "Thiên thần", "😇"], ["devil", "Sừng xinh", "😈"], ["rainbow", "Cầu vồng", "🌈"],
  ["bubbles", "Bong bóng", "🫧"], ["snow", "Tuyết", "❄️"], ["confetti", "Lễ hội", "🎉"],
];
export const BEAUTY_PRESETS = [
  {id:'natural',name:'Tự nhiên',icon:'✧',patch:{soft:true,smooth:.48,blemish:.4,whiten:.12,blush:.08,eyes:.06,lips:.03}},
  {id:'glass',name:'Da căng',icon:'✨',patch:{soft:true,smooth:.78,blemish:.85,whiten:.18,blush:.12,eyes:.08,lips:.05}},
  {id:'peach',name:'Đào',icon:'🌸',patch:{soft:true,smooth:.62,blemish:.65,whiten:.14,blush:.38,eyes:.14,lips:.13}},
  {id:'doll',name:'Búp bê',icon:'🎀',patch:{soft:true,smooth:.68,blemish:.7,whiten:.12,blush:.24,eyes:.72,lips:.27}},
  {id:'eyes',name:'Mắt to',icon:'👀',patch:{eyes:.9}}, {id:'lips',name:'Môi đầy',icon:'💋',patch:{lips:.78}},
];

let faceEnginePromise = null;
let lastFaceTimestamp = 0;
function faceEngine() {
  if(!faceEnginePromise) faceEnginePromise=(async()=>{
    const {FaceLandmarker, FilesetResolver}=await import("./vendor/vision/vision_bundle.mjs");
    const wasm=await FilesetResolver.forVisionTasks("/vendor/vision/wasm");
    return FaceLandmarker.createFromOptions(wasm,{baseOptions:{modelAssetPath:"/vendor/vision/face_landmarker.task",delegate:"CPU"},runningMode:"VIDEO",numFaces:1,minFaceDetectionConfidence:0.5,minFacePresenceConfidence:0.5,minTrackingConfidence:0.5});
  })().catch(e=>{faceEnginePromise=null;throw e;});
  return faceEnginePromise;
}
// Bộ xử lý: video gốc → canvas có hiệu ứng → MediaStream mới (giữ nguyên âm thanh).
export function createEffects(rawStream, { width = 540, height = 960, portrait = false, fit = "cover", sourceElement = null } = {}) {
  const video = sourceElement || document.createElement("video");
  if(!sourceElement){video.muted = true;video.playsInline = true;video.srcObject = rawStream;}
  const ready=()=>video.tagName==='IMG'?video.complete&&video.naturalWidth>0:video.readyState>=2;
  const sourceSize=()=>[video.videoWidth||video.naturalWidth||canvas.width,video.videoHeight||video.naturalHeight||canvas.height];
  const canvas = document.createElement("canvas");
  const settings = rawStream?.getVideoTracks?.()[0]?.getSettings?.() || {};
  // Giữ đúng hướng camera: dọc trên điện thoại, ngang trên máy tính.
  const landscape = !portrait && (settings.width || 0) > (settings.height || 0);
  canvas.width = landscape ? height : width;
  canvas.height = landscape ? width : height;
  const outputCanvas=document.createElement("canvas");outputCanvas.width=canvas.width;outputCanvas.height=canvas.height;
  if(sourceElement){const [sw,sh]=sourceSize(),scale=Math.min(1,Math.max(width,height)/Math.max(sw,sh));canvas.width=Math.max(2,Math.round(sw*scale));canvas.height=Math.max(2,Math.round(sh*scale));}
  const outputContext=outputCanvas.getContext("2d");
  const ctx = canvas.getContext("2d");
  const state = { fit, filter: "none", soft: false, smooth: 0.5, blemish:0, whiten: 0, blush: 0, eyes:0, lips:0, auto: false, sticker: "none", mirror: !sourceElement, compare:false, text:"",textY:.8,textSize:.052,textColor:"#ffffff",textStart:0,textEnd:1e9,timeSeconds:0,projectSeconds:1,rotation:0,flipImage:false,zoom:1,zoomEnd:1,keyframed:false,panX:0,panY:0,exposure:0,contrastLevel:1,saturation:1,temperature:0 };
  let autoBright = 1, autoContrast = 1, autoTick = 0;
  const probe = document.createElement("canvas");
  probe.width = 24; probe.height = 32;
  const layer = document.createElement("canvas");
  const tiny = document.createElement("canvas");
  let face = null;
  let detector = null, detecting = false, lastDetection=0, trackingFailed=false;
  let raf = 0, stopped = false;
  let missedFaces=0;
  let statusText="";const statusListeners=new Set();
  const publish=text=>{if(text!==statusText){statusText=text;for(const callback of statusListeners)callback(text);}};
  async function detect() {
    if(stopped || detecting || trackingFailed || (!state.soft && !state.blush && !state.eyes && !state.lips && state.sticker==="none") || !ready() || performance.now()-lastDetection<120)return;
    detecting=true;lastDetection=performance.now();
    try {
      if(!detector){publish("Đang tải nhận diện khuôn mặt…");detector=await faceEngine();}
      if(stopped)return;
      const timestamp=Math.max(performance.now(),lastFaceTimestamp+1);lastFaceTimestamp=timestamp;
      const points=detector.detectForVideo(video,timestamp).faceLandmarks[0];
      if(!points){if(++missedFaces>=3){face=null;publish("Đưa khuôn mặt vào khung hình");}return;}
      missedFaces=0;
      const [x,y,w,h]=cover();
      const project=p=>({x:state.mirror?canvas.width-(x+p.x*w):x+p.x*w,y:y+p.y*h});
      const projected=points.map(project),xs=projected.map(p=>p.x),ys=projected.map(p=>p.y);
      let left=project(points[33]),right=project(points[263]);if(left.x>right.x)[left,right]=[right,left];
      const next={x:Math.min(...xs),y:Math.min(...ys),width:Math.max(...xs)-Math.min(...xs),height:Math.max(...ys)-Math.min(...ys),eyeY:(left.y+right.y)/2,angle:Math.atan2(right.y-left.y,right.x-left.x)};
      if(face)for(const key of ["x","y","width","height","eyeY","angle"])next[key]=face[key]*0.45+next[key]*0.55;
      next.leftEye=project({x:(points[33].x+points[133].x)/2,y:(points[33].y+points[133].y)/2});
      next.rightEye=project({x:(points[263].x+points[362].x)/2,y:(points[263].y+points[362].y)/2});
      next.mouth=project({x:(points[13].x+points[14].x)/2,y:(points[13].y+points[14].y)/2});
      if(face)for(const key of ['leftEye','rightEye','mouth'])if(face[key])for(const axis of ['x','y'])next[key][axis]=face[key][axis]*.45+next[key][axis]*.55;
      face=next;publish("Đã nhận diện khuôn mặt");
    }catch(e){face=null;trackingFailed=true;publish("Chưa tải được nhận diện. Chọn lại hiệu ứng để thử lại.");}
    finally{detecting=false;}
  }
  function cover() {
    const [vw,vh] = sourceSize();
    // Phủ kín khung đầu ra, cắt đều hai bên nếu camera trả hình ngang.
    const scale = (state.fit === "contain" ? Math.min : Math.max)(canvas.width / vw, canvas.height / vh);
    const w = vw * scale;
    const h = vh * scale;
    return [(canvas.width - w) / 2, (canvas.height - h) / 2, w, h];
  }
  function drawSticker() {
    if(state.sticker==="none")return;
    const emoji = STICKERS.find((s) => s[0] === state.sticker)?.[2];
    if (!emoji) return;
    if(!face)return;
    const box = face;
    const cx = box.x + box.width / 2;
    ctx.save();
    ctx.filter = "none";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    const eyeSpan=Math.abs((box.rightEye?.x||cx+box.width*.2)-(box.leftEye?.x||cx-box.width*.2));
    if (['glasses','round_glasses','neon_glasses','heart_glasses'].includes(state.sticker)) {
      ctx.translate(cx,box.eyeY);ctx.rotate(box.angle);ctx.lineWidth=Math.max(2,box.width*.022);ctx.strokeStyle=state.sticker==='neon_glasses'?'#80ffeb':state.sticker==='heart_glasses'?'#ff78ad':'#24212f';ctx.fillStyle=state.sticker==='glasses'?'#10121be8':'#ffbce026';
      if(state.sticker==='neon_glasses'){ctx.shadowBlur=16;ctx.shadowColor='#27ffe8';}
      for(const side of [-1,1]){ctx.beginPath();const ex=side*eyeSpan*.5,ew=box.width*.22,eh=box.height*.085;
        if(state.sticker==='heart_glasses'){ctx.moveTo(ex,eh);ctx.bezierCurveTo(ex-ew*2,-eh*.1,ex-ew,-eh*2,ex,-eh*.6);ctx.bezierCurveTo(ex+ew,-eh*2,ex+ew*2,-eh*.1,ex,eh);}
        else ctx.ellipse(ex,0,ew,state.sticker==='round_glasses'?ew:eh,0,0,Math.PI*2);ctx.fill();ctx.stroke();}
      ctx.beginPath();ctx.moveTo(-eyeSpan*.12,0);ctx.quadraticCurveTo(0,-box.height*.045,eyeSpan*.12,0);ctx.stroke();
    } else if(['cat','bunny','dog','devil'].includes(state.sticker)){
      ctx.translate(cx,box.y+box.height*.1);ctx.rotate(box.angle);for(const side of [-1,1]){ctx.fillStyle=state.sticker==='devil'?'#ff466f':state.sticker==='cat'?'#49374a':'#ffecf4';ctx.beginPath();if(state.sticker==='cat'||state.sticker==='devil'){ctx.moveTo(side*box.width*.2,0);ctx.lineTo(side*box.width*.46,-box.height*.27);ctx.lineTo(side*box.width*.5,box.height*.07);ctx.closePath();}else ctx.ellipse(side*box.width*.28,-box.height*.12,box.width*.1,box.height*(state.sticker==='bunny'?.29:.18),side*.2,0,Math.PI*2);ctx.fill();}
    } else if(['crown','halo','flowers','bow','rainbow'].includes(state.sticker)){
      ctx.font=Math.round(box.width*.65)+'px serif';ctx.fillText(emoji,cx,box.y-box.height*.13);
    } else {
      const count=state.sticker==='confetti'?12:state.sticker==='snow'?9:6,t=performance.now()/700;ctx.font=Math.round(box.width*.25)+'px serif';
      for(let i=0;i<count;i++){const a=t+i*Math.PI*2/count;ctx.globalAlpha=.55+.45*Math.sin(t*1.3+i)**2;ctx.fillText(emoji,cx+Math.cos(a)*box.width*(state.sticker==='bubbles'?.7:.82),box.y+box.height*.42+Math.sin(a)*box.height*.7);}
    }
    ctx.restore();
  }
  const warp=document.createElement('canvas');
  function magnify(point,rx,ry,amount){
    warp.width=Math.ceil(rx*2);warp.height=Math.ceil(ry*2);const g=warp.getContext('2d');g.clearRect(0,0,warp.width,warp.height);
    const zoom=1+Math.min(1,amount)*.48;
    g.drawImage(canvas,point.x-rx/zoom,point.y-ry/zoom,rx*2/zoom,ry*2/zoom,0,0,warp.width,warp.height);
    g.globalCompositeOperation='destination-in';g.save();g.scale(warp.width/2,warp.height/2);g.translate(1,1);const mask=g.createRadialGradient(0,0,0,0,0,1);mask.addColorStop(0,'#000');mask.addColorStop(.55,'#000');mask.addColorStop(1,'#0000');g.fillStyle=mask;g.fillRect(-1,-1,2,2);g.restore();
    ctx.drawImage(warp,point.x-rx,point.y-ry,rx*2,ry*2);
  }
  function present(){
    if(!sourceElement&&(outputCanvas.width!==canvas.width||outputCanvas.height!==canvas.height)){outputCanvas.width=canvas.width;outputCanvas.height=canvas.height;}
    const g=outputContext,w=outputCanvas.width,h=outputCanvas.height;g.save();g.setTransform(1,0,0,1,0,0);g.filter='none';g.fillStyle='#000';g.fillRect(0,0,w,h);
    const angle=state.compare?0:state.rotation*Math.PI/180,sideways=Math.abs(Math.sin(angle))>.5,sw=sideways?canvas.height:canvas.width,sh=sideways?canvas.width:canvas.height,progress=Math.max(0,Math.min(1,state.timeSeconds/Math.max(.001,state.projectSeconds))),zoom=state.compare?1:state.keyframed?state.zoom+(state.zoomEnd-state.zoom)*progress:state.zoom,scale=Math.min(w/sw,h/sh)*zoom;
    g.translate(w*(.5+(state.compare?0:state.panX)),h*(.5+(state.compare?0:state.panY)));g.rotate(angle);g.scale(scale*(state.flipImage&&!state.compare?-1:1),scale);g.drawImage(canvas,-canvas.width/2,-canvas.height/2);g.restore();
    if(state.text&&!state.compare&&state.timeSeconds>=state.textStart&&state.timeSeconds<=state.textEnd){g.save();g.textAlign='center';g.textBaseline='middle';g.font='700 '+Math.round(w*state.textSize)+'px sans-serif';g.lineJoin='round';g.lineWidth=w*.008;g.strokeStyle='#000b';g.fillStyle=state.textColor;for(const [i,line] of state.text.split('\n').slice(0,4).entries()){const y=h*state.textY+i*w*state.textSize*1.23;g.strokeText(line.slice(0,45),w/2,y,w*.9);g.fillText(line.slice(0,45),w/2,y,w*.9);}g.restore();}
  }
  let frame = 0;
  function draw() {
    if (stopped) return;
    if (ready()) {
      // iPhone hay báo sai hướng trong getSettings(): lấy theo khung hình thật để không bị cắt phóng to.
      const [vw,vh] = sourceSize();
      if (!portrait && vw && vh && (vw > vh) !== (canvas.width > canvas.height)) { const t = canvas.width; canvas.width = canvas.height; canvas.height = t; }
      const [x, y, w, h] = cover();
      let base = FILTERS.find((f) => f[0] === state.filter)?.[2] || "none";
      // Sáng da + AI cân sáng (chạy trên máy, không gửi ảnh đi đâu)
      const extra = (state.whiten ? ` brightness(${(1 + state.whiten * 0.1).toFixed(3)}) saturate(${(1 - state.whiten * 0.12).toFixed(3)})` : "") + (state.auto ? ` brightness(${autoBright.toFixed(3)}) contrast(${autoContrast.toFixed(3)})` : "");
      const grading=` brightness(${Math.max(.1,1+state.exposure*.4)}) contrast(${state.contrastLevel}) saturate(${state.saturation}) sepia(${Math.max(0,state.temperature)*.18})`;
      base=(base==='none'?'':base)+extra+grading;
      ctx.save();
      if (state.mirror) {
        ctx.translate(canvas.width, 0);
        ctx.scale(-1, 1);
      }
      ctx.filter = state.compare?'none':base;
      ctx.drawImage(video, x, y, w, h);
      ctx.restore();
      if(state.compare){detect();present();raf=requestAnimationFrame(draw);return;}
      if (state.soft && face) {
        // Mịn da: lớp mờ trong vùng mặt, mờ dần ra viền (mặt nạ chuyển sắc) để không lộ ranh giới.
        if (layer.width !== canvas.width || layer.height !== canvas.height) { layer.width = canvas.width; layer.height = canvas.height; }
        const l = layer.getContext("2d");
        l.globalCompositeOperation = "source-over";
        l.clearRect(0, 0, layer.width, layer.height);
        l.save();
        if (state.mirror) { l.translate(layer.width, 0); l.scale(-1, 1); }
        l.filter = (base === "none" ? "" : base + " ") + "blur(" + (2 + state.smooth * 4 + state.blemish * 2).toFixed(1) + "px)";
        l.drawImage(video, x, y, w, h);
        l.restore();
        const cxF = face.x + face.width / 2, cyF = face.y + face.height * 0.55, r = Math.max(face.width, face.height) * 0.62;
        const g = l.createRadialGradient(cxF, cyF, r * 0.35, cxF, cyF, r);
        g.addColorStop(0, "#000"); g.addColorStop(1, "#0000");
        l.globalCompositeOperation = "destination-in";
        l.fillStyle = g;
        l.fillRect(0, 0, layer.width, layer.height);
        // Keep eyes, lips and their sharp edges out of the skin-smoothing layer.
        l.globalCompositeOperation='destination-out';l.filter='none';
        for(const [point,rx,ry] of [[face.leftEye,face.width*.16,face.height*.07],[face.rightEye,face.width*.16,face.height*.07],[face.mouth,face.width*.2,face.height*.09]])if(point){
          l.save();l.translate(point.x,point.y);l.rotate(face.angle);l.scale(rx,ry);const hole=l.createRadialGradient(0,0,0,0,0,1);hole.addColorStop(0,'#000');hole.addColorStop(.65,'#000');hole.addColorStop(1,'#0000');l.fillStyle=hole;l.fillRect(-1,-1,2,2);l.restore();
        }
        ctx.save();
        ctx.globalAlpha = Math.min(.92,0.25 + state.smooth * 0.48 + state.blemish*.15);
        ctx.drawImage(layer, 0, 0);
        ctx.restore();
      }
      if (state.blush > 0.01 && face) {
        for (const side of [-1, 1]) {
          const bx = face.x + face.width / 2 + side * face.width * 0.27, by = face.y + face.height * 0.62, br = face.width * 0.17;
          const g = ctx.createRadialGradient(bx, by, 0, bx, by, br);
          g.addColorStop(0, `rgba(255,105,140,${(state.blush * 0.45).toFixed(2)})`); g.addColorStop(1, "rgba(255,105,140,0)");
          ctx.fillStyle = g; ctx.fillRect(bx - br, by - br, br * 2, br * 2);
        }
      }
      if (state.auto && autoTick++ % 30 === 0) {
        const p = probe.getContext("2d", { willReadFrequently: true });
        p.drawImage(video, 0, 0, probe.width, probe.height);
        const d = p.getImageData(0, 0, probe.width, probe.height).data;
        let sum = 0, sq = 0;
        for (let i = 0; i < d.length; i += 4) { const lum = d[i] * 0.299 + d[i + 1] * 0.587 + d[i + 2] * 0.114; sum += lum; sq += lum * lum; }
        const n = d.length / 4, mean = sum / n, std = Math.sqrt(Math.max(1, sq / n - mean * mean));
        autoBright = Math.min(1.25, Math.max(0.88, 1 + (125 - mean) / 400));
        autoContrast = Math.min(1.2, Math.max(0.92, 1 + (55 - std) / 300));
      }
      if(face){
        for(const [point,rx,ry,strength] of [[face.leftEye,face.width*.19,face.height*.11,state.eyes],[face.rightEye,face.width*.19,face.height*.11,state.eyes],[face.mouth,face.width*.24,face.height*.14,state.lips]])if(point&&strength>.01)magnify(point,rx,ry,strength);
      }
      detect();
      drawSticker();
      present();
    }
    raf = requestAnimationFrame(draw);
  }
  video.play?.().catch(() => {});
  draw();
  // requestAnimationFrame dừng khi tab ẩn; dùng thêm hẹn giờ để livestream không bị đứng hình.
  const keepAlive = setInterval(() => {
    if (document.hidden && !stopped) {
      cancelAnimationFrame(raf);
      draw();
    }
  }, 66);
  const output = outputCanvas.captureStream(30);
  for (const track of rawStream?.getAudioTracks?.()||[]) output.addTrack(track);
  return {
    stream: output,
    canvas:outputCanvas,
    state,
    get faceSupported(){return !!detector;},
    get faceBox(){return face ? {...face} : null;},
    onStatus(callback){statusListeners.add(callback);callback(statusText);return ()=>statusListeners.delete(callback);},
    set(patch) {
      Object.assign(state, patch);
      trackingFailed=false;
      if(!state.soft && !state.blush && !state.eyes && !state.lips && state.sticker==="none"){face=null;publish("");}else detect();
    },
    stop() {
      stopped = true;
      statusListeners.clear();
      cancelAnimationFrame(raf);
      clearInterval(keepAlive);
      output.getVideoTracks().forEach((t) => t.stop());
      if(!sourceElement)video.srcObject = null;
    },
  };
}

// Thanh chọn hiệu ứng dùng chung (bộ lọc, làm mịn, sticker).
export function effectPicker(fx, { dark = true } = {}) {
  const box = document.createElement("div");
  box.className = "fx-picker" + (dark ? " dark" : "");
  const row = (items, key) => {
    const r = document.createElement("div");
    r.className = "fx-row";
    r.setAttribute("role", "group");
    r.setAttribute("aria-label", key === "filter" ? "Bộ lọc màu" : "Sticker khuôn mặt");
    for (const [id, label, sample] of items) {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "fx-chip" + (fx.state[key] === id ? " on" : "");
      b.setAttribute("aria-pressed", String(fx.state[key] === id));
      b.textContent = key === "sticker" && sample ? sample + " " + label : label;
      b.onclick = () => {
        fx.set({ [key]: id });
        for (const c of r.children) {
          c.classList.toggle("on", c === b);
          c.setAttribute("aria-pressed", String(c === b));
        }
      };
      r.append(b);
    }
    return r;
  };
  const soft = document.createElement("button");
  soft.type = "button";
  soft.className = "fx-chip" + (fx.state.soft ? " on" : "");
  soft.textContent = "✨ Làm mịn da";
  soft.setAttribute("aria-pressed", String(fx.state.soft));
  const sliders=new Map();
  const syncBeauty=()=>{soft.classList.toggle("on",fx.state.soft);soft.setAttribute("aria-pressed",String(fx.state.soft));for(const [key,slider] of sliders)slider.value=fx.state[key];};
  soft.onclick = () => {
    fx.set(fx.state.soft?{soft:false,eyes:0,lips:0,whiten:0,blush:0}:BEAUTY_PRESETS[1].patch);
    soft.classList.toggle("on", fx.state.soft);
    soft.setAttribute("aria-pressed", String(fx.state.soft));
    syncBeauty();
  };
  const filters = row(FILTERS, "filter");
  filters.prepend(soft);
  box.append(filters, row(STICKERS, "sticker"));
  const beauty=document.createElement('div');beauty.className='fx-row';beauty.setAttribute('aria-label','Làm đẹp khuôn mặt');
  for(const item of BEAUTY_PRESETS){const b=document.createElement('button');b.type='button';b.className='fx-chip';b.textContent=item.icon+' '+item.name;b.onclick=()=>{fx.set(item.patch);syncBeauty();};beauty.append(b);}
  box.append(beauty);
  for(const [key,label] of [['smooth','Mịn da'],['blemish','Giảm đốm'],['eyes','Mắt to'],['lips','Môi đầy']]){const line=document.createElement('label');line.className='fx-slider';line.textContent=label;const range=document.createElement('input');range.type='range';range.min='0';range.max='1';range.step='.01';range.value=fx.state[key];range.setAttribute('aria-label',label);range.oninput=()=>fx.set({[key]:Number(range.value),...(key==='smooth'||key==='blemish'?{soft:true}:{})});sliders.set(key,range);line.append(range);box.append(line);}

  const note=document.createElement("p");note.className="fx-note";
  fx.onStatus(text=>{note.textContent=text;note.hidden=!text;});box.append(note);
  return box;
}

function pickMime() {
  for (const t of ["video/mp4;codecs=avc1.42E01E,mp4a.40.2", "video/mp4;codecs=avc1", "video/mp4"])
    if (window.MediaRecorder?.isTypeSupported?.(t)) return t;
  return null;
}

// Kinnect Studio: quay video và lên sóng. onDone(blob, caption) khi bấm Đăng; onLive() khi chọn tab LIVE.
const ICON = {
  flip: '<svg viewBox="0 0 24 24"><path d="M4 12a8 8 0 0113.7-5.6L20 8.5M20 4v4.5h-4.5M20 12a8 8 0 01-13.7 5.6L4 15.5M4 20v-4.5h4.5"/></svg>',
  timer: '<svg viewBox="0 0 24 24"><circle cx="12" cy="13" r="8"/><path d="M12 9v4l2.5 2.5M9 2h6"/></svg>',
  filter: '<svg viewBox="0 0 24 24"><circle cx="9" cy="9" r="5.5"/><circle cx="15" cy="9" r="5.5"/><circle cx="12" cy="15" r="5.5"/></svg>',
  beauty: '<svg viewBox="0 0 24 24"><circle cx="10" cy="8" r="4"/><path d="M3 21a7 7 0 0114 0M18 3l.8 1.7L20.5 5.5l-1.7.8L18 8l-.8-1.7-1.7-.8 1.7-.8z"/></svg>',
};
// Hiệu ứng nhanh: sticker bám mặt + một số bộ lọc
const CAROUSEL = [
  ["none", "none", "Gốc", "🙂"],
  ["sticker", "glasses", "Kính", "😎"],
  ["sticker", "hearts", "Tim", "😍"],
  ["sticker", "cat", "Mèo", "🐱"],
  ["sticker", "crown", "Vương miện", "👑"],
  ["sticker", "sparkle", "Lấp lánh", "✨"],
  ["filter", "vivid", "Rực rỡ", "🌈"],
  ["filter", "mono", "Đen trắng", "🖤"],
  ["filter", "vintage", "Cổ điển", "📷"],
];

async function photoSource(file) {
  const url=URL.createObjectURL(file),image=new Image();
  try { image.src=url;await image.decode(); } finally { URL.revokeObjectURL(url); }
  const canvas=document.createElement("canvas");canvas.width=540;canvas.height=960;
  const ctx=canvas.getContext("2d");
  const draw=()=>{ctx.fillStyle="#101014";ctx.fillRect(0,0,540,960);const scale=Math.min(540/image.naturalWidth,960/image.naturalHeight);const w=image.naturalWidth*scale,h=image.naturalHeight*scale;ctx.drawImage(image,(540-w)/2,(960-h)/2,w,h);};
  draw();const timer=setInterval(draw,33),stream=canvas.captureStream(30);
  return {stream,stop(){clearInterval(timer);stream.getTracks().forEach(t=>t.stop());}};
}
// Lấy khung gốc của camera (không để trình duyệt cắt/phóng to) và đưa zoom về mức rộng nhất.
function cameraConstraints(facing) {
  // Điện thoại cầm dọc (iPhone): đặt kích thước sẽ nhận khung ngang bị cắt; chỉ xin hướng camera để có khung dọc.
  if (matchMedia("(pointer: coarse)").matches && innerHeight > innerWidth) return { facingMode: facing };
  return { facingMode: facing, width: { ideal: 1280 }, height: { ideal: 720 }, resizeMode: "none" };
}
async function widestZoom(stream) {
  const track = stream.getVideoTracks()[0];
  const caps = track?.getCapabilities?.() || {};
  if (caps.zoom) try { await track.applyConstraints({ advanced: [{ zoom: caps.zoom.min }] }); } catch {}
}
export async function openStudio({ onDone, onLive, notify = () => {}, mode: startMode = "camera", story = false, photo = null }) {
  if (!photo && !navigator.mediaDevices?.getUserMedia) {
    notify("Trình duyệt không cho dùng camera. Hãy mở Kinnect bằng HTTPS (app.kinnect.io.vn).");
    return;
  }
  const mime = pickMime();
  let facing = "user";
  let raw, still = null;
  try {
    if(photo) { still=await photoSource(photo);raw=still.stream; }
    else raw = await navigator.mediaDevices.getUserMedia({
      video: cameraConstraints(facing),
      audio: true,
    });
    await widestZoom(raw);
  } catch (e) {
    notify("Không mở được camera/micro: " + e.message);
    return;
  }
  let fx = createEffects(raw);
  if(still)fx.set({mirror:false});
  let maxSec = photo || story ? 15 : 60;
  let delay = 0;
  const root = document.createElement("div");
  root.className = "studio tt";
  root.setAttribute("role", "dialog");
  root.setAttribute("aria-modal", "true");
  root.setAttribute("aria-label", story ? "Tạo tin" : "Quay video");
  const rail = (key, label) =>
    `<button type="button" class="tt-tool" data-tool="${key}" aria-label="${label}">${ICON[key]}<small>${label}</small></button>`;
  root.innerHTML =
    '<div class="tt-card">' +
    '<div class="tt-stage"></div>' +
    '<div class="tt-progress"><i></i></div>' +
    '<button type="button" class="tt-x" aria-label="Đóng">✕</button>' +
    '<span class="tt-time" aria-live="polite"></span>' +
    '<button type="button" class="tt-sound" aria-label="Nhạc nền">🎵 <span>Nhạc nền</span></button>' +
    '<div class="tt-rail">' + rail("flip", "Lật") + rail("timer", "Hẹn giờ") + rail("filter", "Bộ lọc") + rail("beauty", "Làm đẹp") + "</div>" +
    '<div class="tt-sheet" hidden></div>' +
    '<div class="tt-count" hidden></div>' +
    '<div class="tt-modes" role="group" aria-label="Thời lượng"><button type="button" data-sec="60" class="on">60 giây</button><button type="button" data-sec="15">15 giây</button></div>' +
    '<form class="tt-golive" hidden><input class="tt-title" maxlength="100" placeholder="Bạn muốn trò chuyện về gì?" aria-label="Tiêu đề buổi live" required><button type="submit" class="tt-golive-btn">Lên sóng</button></form>' +
    '<div class="tt-shutter-row"><div class="tt-carousel" role="group" aria-label="Hiệu ứng"></div><button type="button" class="tt-shutter" aria-label="Bắt đầu quay"><span></span></button></div>' +
    "</div>" +
    '<div class="tt-bottom"><label class="tt-gallery" aria-label="Tải video từ máy"><input type="file" accept="video/mp4,video/quicktime"><span>🖼️</span><small>Tải lên</small></label>' +
    '<div class="tt-tabs" role="group" aria-label="Chế độ"><button type="button" class="tt-mode on" data-mode="camera">Quay video</button><button type="button" class="tt-mode" data-mode="live">Phát trực tiếp</button></div><span class="tt-spacer"></span></div>' +
    '<form class="tt-post" hidden><div class="tt-post-head"><button type="button" class="tt-back" aria-label="Quay lại">‹</button><b>Chia sẻ video</b><span></span></div>' +
    '<div class="tt-post-body"><textarea class="tt-caption" maxlength="500" rows="4" placeholder="Viết vài dòng về video…" aria-label="Chú thích video"></textarea><video class="tt-preview" playsinline loop muted autoplay></video></div>' +
    '<div class="tt-post-actions"><button type="button" class="tt-retake">Quay lại</button><button type="submit" class="tt-publish">Chia sẻ</button></div></form>';
  document.body.append(root);
  document.body.classList.add("studio-open");
  const $ = (s) => root.querySelector(s);
  const trackingNote=document.createElement("p");trackingNote.className="tt-face-status";$(".tt-card").append(trackingNote);let unsubscribeStatus=null;
  const mount = () => {$(".tt-stage").replaceChildren(fx.canvas);unsubscribeStatus?.();unsubscribeStatus=fx.onStatus(text=>{trackingNote.textContent=text;trackingNote.hidden=!text;});};
  mount();
  if(story){
    $('[data-mode="live"]').hidden=true;
    $('[data-mode="camera"]').textContent=photo?"Tin ảnh + nhạc":"Quay tin";
    $(".tt-post-head b").textContent="Xem lại tin";
    $(".tt-publish").textContent="Đăng tin";
    $(".tt-gallery input").accept="image/jpeg,image/png,image/webp,video/mp4";
    $(".tt-gallery").setAttribute("aria-label","Chọn ảnh hoặc video");
    $(".tt-caption").placeholder="Viết về tin của bạn…";
    $(".tt-preview").muted=false;
    $(".tt-preview").controls=true;
    for(const b of root.querySelectorAll(".tt-modes button"))b.classList.toggle("on",Number(b.dataset.sec)===maxSec);
  }
  if(photo){$(".tt-shutter").setAttribute("aria-label","Tạo tin ảnh");$('[data-tool="flip"]').hidden=true;}
  // Dải hiệu ứng phía trên nút chụp
  const carousel = $(".tt-carousel");
  let picked = "none";
  for (const [kind, id, label, emoji] of CAROUSEL) {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "tt-fx" + (id === picked ? " on" : "");
    b.setAttribute("aria-label", label);
    b.setAttribute("aria-pressed", String(id === picked));
    b.innerHTML = "<span>" + emoji + "</span><small>" + label + "</small>";
    b.onclick = () => {
      picked = id;
      if (kind === "none") fx.set({ sticker: "none", filter: "none" });
      else fx.set({ [kind]: id });
      for (const c of carousel.children) {
        c.classList.toggle("on", c === b);
        c.setAttribute("aria-pressed", String(c === b));
      }
    };
    carousel.append(b);
  }
  // Âm nhạc: thư viện chung trên máy chủ hoặc nhạc của chính người dùng (trộn ngay trên máy)
  const music = new Audio();
  music.loop = true;
  music.preload = "auto";
  let musicUrl = "";
  let musicOwnUrl = "";
  const soundLabel = $(".tt-sound span");
  function setMusic(url, title) {
    music.pause();
    musicUrl = url || "";
    soundLabel.textContent = title || "Nhạc nền";
    $(".tt-sound").classList.toggle("on", !!url);
    if (url) {
      music.src = url;
      music.currentTime = 0;
      music.play().catch(() => {});
    } else music.removeAttribute("src");
  }
  // Bảng chọn từ cột công cụ
  const sheet = $(".tt-sheet");
  // Chọn nhạc kiểu Facebook: bảng toàn màn, tìm kiếm, tab Thư viện / Nhạc của bạn, nghe thử từng bài, nút "Dùng bài này".
  async function openSound() {
    if (document.querySelector(".mp")) return;
    const box = document.createElement("div");
    box.className = "mp";
    box.setAttribute("role", "dialog");
    box.setAttribute("aria-label", "Chọn nhạc");
    box.innerHTML =
      '<div class="mp-sheet"><div class="mp-grip"></div>' +
      '<div class="mp-head"><button type="button" class="mp-close" aria-label="Đóng">✕</button><h2>Âm nhạc</h2><span></span></div>' +
      '<label class="mp-search"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg><input type="search" placeholder="Tìm bài hát hoặc nghệ sĩ" aria-label="Tìm nhạc"></label>' +
      '<div class="mp-tabs" role="tablist"><button type="button" class="on" data-tab="lib">Thư viện</button><button type="button" data-tab="own">Nhạc của bạn</button></div>' +
      '<div class="mp-list" role="list"></div>' +
      '<div class="mp-bar" hidden><div class="mp-now"><b></b><small></small></div><button type="button" class="mp-use">Dùng bài này</button></div></div>';
    const sheetEl = box.querySelector(".mp-sheet"), list = box.querySelector(".mp-list"), bar = box.querySelector(".mp-bar");
    const preview = new Audio();
    let tracks = [], tab = "lib", picked = null, playing = null, shown = 60;
    const close = () => { preview.pause(); box.classList.remove("open"); setTimeout(() => box.remove(), 220); };
    box.querySelector(".mp-close").onclick = close;
    box.onclick = (e) => { if (e.target === box) close(); };
    const hue = (t) => { let h = 0; for (const c of t) h = (h * 31 + c.charCodeAt(0)) % 360; return h; };
    const icon = (on) => on ? '<svg viewBox="0 0 24 24"><rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/></svg>' : '<svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg>';
    function choose(t) {
      picked = t;
      bar.hidden = false;
      bar.querySelector("b").textContent = t.title;
      bar.querySelector("small").textContent = t.artist || "Nhạc của bạn";
      render();
    }
    function play(t, btn) {
      if (playing === t.url) { preview.pause(); playing = null; render(); return; }
      preview.src = t.url; preview.currentTime = 0; preview.play().catch(() => {}); playing = t.url; choose(t);
    }
    preview.onended = () => { playing = null; render(); };
    function render() {
      list.replaceChildren();
      const q = box.querySelector(".mp-search input").value.trim().toLocaleLowerCase("vi");
      if (tab === "own") {
        const up = document.createElement("label");
        up.className = "mp-upload";
        up.innerHTML = '<span class="mp-art own">＋</span><span class="mp-meta"><b>Chọn nhạc trong máy</b><small>MP3, M4A… tối đa 20 MB · chỉ dùng trên máy bạn</small></span><input type="file" accept="audio/*" hidden>';
        up.querySelector("input").onchange = (e) => {
          const f = e.target.files[0];
          if (!f) return;
          if (f.size > 20 * 1024 * 1024) return notify("File nhạc tối đa 20 MB.");
          if (musicOwnUrl) URL.revokeObjectURL(musicOwnUrl);
          musicOwnUrl = URL.createObjectURL(f);
          const t = { url: musicOwnUrl, title: f.name.replace(/\.[^.]+$/, "").replace(/[_-]+/g, " "), artist: "" };
          ownTracks.unshift(t);
          choose(t);
        };
        list.append(up);
      }
      const rows = (tab === "own" ? ownTracks : tracks).filter((t) => !q || (t.title + " " + (t.artist || "")).toLocaleLowerCase("vi").includes(q));
      if (!rows.length && tab === "lib") { const n = document.createElement("p"); n.className = "mp-empty"; n.textContent = q ? "Không tìm thấy bài phù hợp." : "Thư viện chưa có bài nào."; list.append(n); }
      for (const t of rows.slice(0, shown)) {
        const row = document.createElement("div");
        row.className = "mp-row" + (picked && picked.url === t.url ? " on" : "");
        row.setAttribute("role", "listitem");
        row.innerHTML = '<span class="mp-art">♪</span><span class="mp-meta"><b></b><small></small></span><button type="button" class="mp-play" aria-label="Nghe thử">' + icon(playing === t.url) + '</button>';
        row.querySelector(".mp-art").style.setProperty("--h", String(hue(t.title)));
        row.querySelector("b").textContent = t.title;
        row.querySelector("small").textContent = [t.artist, t.license].filter(Boolean).join(" · ") || "Nhạc của bạn";
        row.querySelector(".mp-play").onclick = (e) => { e.stopPropagation(); play(t); };
        row.onclick = () => play(t);
        list.append(row);
      }
      if (rows.length > shown) {
        const more = document.createElement("button");
        more.type = "button"; more.className = "mp-more"; more.textContent = "Xem thêm (" + (rows.length - shown) + " bài)";
        more.onclick = () => { shown += 60; render(); };
        list.append(more);
      }
    }
    box.querySelectorAll(".mp-tabs button").forEach((b) => (b.onclick = () => { tab = b.dataset.tab; box.querySelectorAll(".mp-tabs button").forEach((x) => x.classList.toggle("on", x === b)); render(); }));
    box.querySelector(".mp-search input").oninput = () => { shown = 60; render(); };
    box.querySelector(".mp-use").onclick = () => { if (picked) setMusic(picked.url, picked.title); close(); };
    if (musicUrl) {
      const off = document.createElement("button");
      off.type = "button"; off.className = "mp-off"; off.textContent = "Bỏ nhạc nền";
      off.onclick = () => { setMusic("", ""); close(); };
      sheetEl.querySelector(".mp-head span").replaceWith(off);
    }
    (document.querySelector("dialog[open]") || document.body).append(box);
    requestAnimationFrame(() => box.classList.add("open"));
    render();
    try {
      const r = await fetch("/api/music", { credentials: "same-origin" });
      tracks = (r.ok ? (await r.json()).tracks : []) || [];
      render();
    } catch {}
  }
  const ownTracks = [];
  $(".tt-sound").onclick = openSound;
  // Bảng hiệu ứng kiểu app: bộ lọc có ảnh xem trước, làm đẹp dạng nút tròn + thanh trượt, hẹn giờ.
  let beautyKey = "smooth";
  function openSheet(kind) {
    if (!sheet.hidden && sheet.dataset.kind === kind) return (sheet.hidden = true);
    sheet.dataset.kind = kind;
    sheet.replaceChildren();
    sheet.classList.add("fxp");
    const slider = (label, value, onInput) => {
      const wrap = document.createElement("label");
      wrap.className = "fxp-slider";
      wrap.innerHTML = "<span></span><input type=\"range\" min=\"0\" max=\"100\"><b></b>";
      wrap.querySelector("span").textContent = label;
      const input = wrap.querySelector("input"), out = wrap.querySelector("b");
      input.value = String(Math.round(value * 100));
      out.textContent = input.value;
      input.oninput = () => { out.textContent = input.value; onInput(Number(input.value) / 100); };
      return wrap;
    };
    if (kind === "filter") {
      const row = document.createElement("div");
      row.className = "fxp-filters";
      const src = fx.canvas;
      for (const [id, label, css] of FILTERS) {
        const b = document.createElement("button");
        b.type = "button";
        b.className = "fxp-filter" + (fx.state.filter === id ? " on" : "");
        const thumb = document.createElement("canvas");
        thumb.width = 60; thumb.height = 80;
        const t = thumb.getContext("2d");
        try { t.filter = css; t.drawImage(src, src.width * 0.15, src.height * 0.12, src.width * 0.7, src.height * 0.76, 0, 0, 60, 80); } catch {}
        const name = document.createElement("span");
        name.textContent = label;
        b.append(thumb, name);
        b.onclick = () => { fx.set({ filter: id }); for (const c of row.children) c.classList.toggle("on", c === b); };
        row.append(b);
      }
      sheet.append(row);
    }
    if (kind === "beauty") {
      const items = [["auto", "🤖", "AI"], ["off", "⭕", "Tắt"], ["smooth", "✨", "Mịn da"], ["whiten", "☀️", "Sáng da"], ["blush", "🌸", "Má hồng"]];
      const value = (k) => (k === "smooth" ? (fx.state.soft ? fx.state.smooth : 0) : fx.state[k] || 0);
      const set = (k, v) => {
        if (k === "smooth") fx.set({ soft: v > 0.01, smooth: v });
        else fx.set({ [k]: v });
      };
      if (["smooth", "whiten", "blush"].includes(beautyKey)) sheet.append(slider(items.find((x) => x[0] === beautyKey)[2], value(beautyKey), (v) => set(beautyKey, v)));
      const row = document.createElement("div");
      row.className = "fxp-beauty";
      for (const [k, glyph, label] of items) {
        const on = k === "auto" ? fx.state.auto : k === "off" ? !fx.state.soft && !fx.state.whiten && !fx.state.blush : beautyKey === k && value(k) > 0;
        const b = document.createElement("button");
        b.type = "button";
        b.className = "fxp-chip" + (on ? " on" : "");
        b.innerHTML = "<i></i><span></span>";
        b.querySelector("i").textContent = glyph;
        b.querySelector("span").textContent = k === "auto" && fx.state.auto ? "AI: bật" : label;
        b.onclick = () => {
          if (k === "auto") {
            const next = !fx.state.auto;
            fx.set(next ? { auto: true, soft: true, smooth: 0.6, whiten: 0.25, blush: 0.15 } : { auto: false });
          } else if (k === "off") fx.set({ soft: false, whiten: 0, blush: 0, auto: false });
          else { beautyKey = k; if (!value(k)) set(k, k === "smooth" ? 0.5 : 0.3); }
          sheet.dataset.kind = "";
          openSheet("beauty");
        };
        row.append(b);
      }
      sheet.append(row);
      const note = document.createElement("p");
      note.className = "fxp-note";
      note.textContent = "AI làm đẹp và nhận diện khuôn mặt chạy ngay trên máy bạn.";
      sheet.append(note);
    }
    if (kind === "timer") {
      const row = document.createElement("div");
      row.className = "fxp-beauty";
      for (const s2 of [0, 3, 10]) {
        const b = document.createElement("button");
        b.type = "button";
        b.className = "fxp-chip" + (delay === s2 ? " on" : "");
        b.innerHTML = "<i></i><span></span>";
        b.querySelector("i").textContent = s2 ? String(s2) : "⏱";
        b.querySelector("span").textContent = s2 ? s2 + " giây" : "Tắt";
        b.onclick = () => { delay = s2; $('[data-tool="timer"]').classList.toggle("on", !!s2); for (const c of row.children) c.classList.toggle("on", c === b); };
        row.append(b);
      }
      sheet.append(row);
    }
    sheet.hidden = false;
  }
  for (const b of root.querySelectorAll(".tt-tool")) {
    if (b.dataset.tool === "flip") continue;
    b.onclick = () => openSheet(b.dataset.tool);
  }
  // Thời lượng
  for (const b of root.querySelectorAll(".tt-modes button"))
    b.onclick = () => {
      if (recorder?.state === "recording") return;
      maxSec = Number(b.dataset.sec);
      for (const c of root.querySelectorAll(".tt-modes button")) c.classList.toggle("on", c === b);
    };
  let recorder = null;
  let chunks = [];
  let started = 0;
  let tick = 0;
  let blobUrl = "";
  let pendingBlob = null;
  let counting = 0;
  let audioCtx = null;
  let musicNode = null;
  let closed = false;
  let flipping = false;
  function close() {
    if (closed) return;
    closed = true;
    try {
      recorder?.state === "recording" && recorder.stop();
    } catch {}
    clearInterval(tick);
    clearInterval(counting);
    music.pause();
    music.removeAttribute("src");
    if (musicOwnUrl) URL.revokeObjectURL(musicOwnUrl);
    audioCtx?.close?.();
    fx.stop();
    still?.stop();
    raw.getTracks().forEach((t) => t.stop());
    if (blobUrl) URL.revokeObjectURL(blobUrl);
    root.remove();
    document.body.classList.remove("studio-open");
    document.removeEventListener("keydown", onKey);
  }
  const onKey = (e) => e.key === "Escape" && close();
  document.addEventListener("keydown", onKey);
  $(".tt-x").onclick = close;
  function setMode(m) {
    if (counting || flipping || recorder?.state === "recording") return;
    root.dataset.mode = m;
    for (const b of root.querySelectorAll(".tt-mode")) b.classList.toggle("on", b.dataset.mode === m);
    $(".tt-golive").hidden = m !== "live";
    sheet.hidden = true;
    if (m === "live") music.pause();
  }
  for (const b of root.querySelectorAll(".tt-mode")) b.onclick = () => recorder?.state !== "recording" && setMode(b.dataset.mode);
  $(".tt-golive").onsubmit = (e) => {
    e.preventDefault();
    const title = $(".tt-title").value.trim();
    if (!title) return $(".tt-title").focus();
    const state = { ...fx.state };
    close();
    onLive?.({ title, state });
  };
  setMode(startMode);
  $('[data-tool="flip"]').onclick = async () => {
    if (closed || flipping || counting || recorder?.state === "recording") return;
    flipping = true;
    facing = facing === "user" ? "environment" : "user";
    try {
      const next = await navigator.mediaDevices.getUserMedia({
        video: cameraConstraints(facing),
        audio: true,
      });
      if (closed) {
        next.getTracks().forEach((t) => t.stop());
        return;
      }
      const keep = { ...fx.state, mirror: facing === "user" };
      fx.stop();
      raw.getTracks().forEach((t) => t.stop());
      raw = next;
      fx = createEffects(raw);
      fx.set(keep);
      mount();
    } catch (e) {
      facing = facing === "user" ? "environment" : "user";
      notify("Không đổi được camera: " + e.message);
    } finally {
      flipping = false;
    }
  };
  function review(blob) {
    pendingBlob = blob;
    if (blobUrl) URL.revokeObjectURL(blobUrl);
    blobUrl = URL.createObjectURL(blob);
    const preview = $(".tt-preview");
    // Xem lại trước khi đăng: có nút phát/dừng, có tiếng, tua được.
    preview.controls = true;
    preview.muted = false;
    preview.src = blobUrl;
    $(".tt-post").hidden = false;
    preview.play().catch(() => { preview.muted = true; preview.play().catch(() => {}); });
  }
  function stopRec() {
    if (recorder?.state === "recording") recorder.stop();
  }
  function startRec() {
    if (closed || flipping) return;
    if (!mime) return notify("Trình duyệt này chưa quay được MP4. Hãy chọn video có sẵn bằng nút Tải lên.");
    sheet.hidden = true;
    chunks = [];
    let recStream = fx.stream;
    if (musicUrl) {
      // Trộn micro + nhạc vào một đường âm thanh
      audioCtx ||= new AudioContext();
      audioCtx.resume?.();
      const dest = audioCtx.createMediaStreamDestination();
      // Đã chọn nhạc thì không thu micro: trên điện thoại micro thu lại tiếng nhạc từ loa gây rè/nhiễu.
      const mic = [];
      if (mic.length) {
        const g = audioCtx.createGain();
        g.gain.value = 0.8;
        audioCtx.createMediaStreamSource(new MediaStream(mic)).connect(g).connect(dest);
      }
      musicNode ||= audioCtx.createMediaElementSource(music);
      musicNode.disconnect();
      musicNode.connect(dest);
      musicNode.connect(audioCtx.destination);
      music.currentTime = 0;
      music.play().catch(() => {});
      recStream = new MediaStream([...fx.stream.getVideoTracks(), ...dest.stream.getAudioTracks()]);
    }
    recorder = new MediaRecorder(recStream, { mimeType: mime, videoBitsPerSecond: 1_200_000, audioBitsPerSecond: 96_000 });
    recorder.ondataavailable = (e) => e.data.size && chunks.push(e.data);
    recorder.onstop = () => {
      clearInterval(tick);
      if (closed) return;
      music.pause();
      root.classList.remove("recording");
      $(".tt-shutter").setAttribute("aria-label", still ? "Tạo tin ảnh" : "Bắt đầu quay");
      $(".tt-progress i").style.width = "0";
      $(".tt-time").textContent = "";
      if ((performance.now() - started) / 1000 < 1) return notify("Video quá ngắn. Quay ít nhất 1 giây.");
      review(new Blob(chunks, { type: "video/mp4" }));
    };
    recorder.start(1000);
    started = performance.now();
    root.classList.add("recording");
    $(".tt-shutter").setAttribute("aria-label", "Dừng quay");
    tick = setInterval(() => {
      const s = (performance.now() - started) / 1000;
      $(".tt-progress i").style.width = Math.min(100, (s / maxSec) * 100) + "%";
      $(".tt-time").textContent = Math.floor(s) + "s";
      if (s >= maxSec - 0.3) stopRec();
    }, 100);
  }
  $(".tt-shutter").onclick = () => {
    if (recorder?.state === "recording") return stopRec();
    if (counting) return;
    if (!delay) return startRec();
    let n = delay;
    const box = $(".tt-count");
    box.hidden = false;
    box.textContent = n;
    counting = setInterval(() => {
      n--;
      if (n > 0) return (box.textContent = n);
      clearInterval(counting);
      counting = 0;
      box.hidden = true;
      startRec();
    }, 1000);
  };
  // Tải video có sẵn từ máy
  $(".tt-gallery input").onchange = async (e) => {
    const f = e.target.files[0];
    e.target.value = "";
    if (!f) return;
    if (f.size > 12 * 1024 * 1024) return notify("Tệp tối đa 12 MB.");
    if(story && f.type.startsWith("image/")){
      try{const next=await photoSource(f);if(closed){next.stop();return;}fx.stop();still?.stop();raw.getTracks().forEach(t=>t.stop());still=next;raw=next.stream;fx=createEffects(raw);fx.set({mirror:false});mount();$(".tt-shutter").setAttribute("aria-label","Tạo tin ảnh");$('[data-tool="flip"]').hidden=true;$('[data-mode="camera"]').textContent="Tin ảnh + nhạc";notify("Chọn nhạc nền rồi bấm Tạo tin ảnh. Bạn có thể dừng khi đủ đoạn nhạc mong muốn.");}catch(err){notify(err.message);}return;
    }
    review(f);
  };
  const back = () => {
    $(".tt-post").hidden = true;
    $(".tt-preview").pause();
  };
  $(".tt-back").onclick = back;
  $(".tt-retake").onclick = back;
  $(".tt-post").onsubmit = async (e) => {
    e.preventDefault();
    if (pendingBlob.size > 12 * 1024 * 1024) return notify("Video vượt 12 MB. Hãy quay ngắn hơn.");
    const btn = $(".tt-publish");
    btn.disabled = true;
    btn.textContent = "Đang đăng…";
    try {
      await onDone(pendingBlob, $(".tt-caption").value, (p) => { btn.textContent = p < 0 ? "Đang chuẩn bị video…" : p < 100 ? "Đang tải lên " + p + "%" : "Đang xử lý…"; });
      close();
    } catch (err) {
      notify(err.message);
      btn.disabled = false;
      btn.textContent = story ? "Đăng tin" : "Chia sẻ";
    }
  };
}
