// Native transport bridge for @polyv/interactions-launch-sdk 0.7.0.
const native = (kind, data) => window.webkit.messageHandlers.platform.postMessage({kind, ...data});
class NativeXHR {
  constructor() { this.headers = {}; this.readyState = 0; this.status = 0; }
  open(method, url) { this.method = method; this.url = url; this.readyState = 1; }
  setRequestHeader(k,v) { this.headers[k] = v; }
  getAllResponseHeaders() { return 'content-type: application/json'; }
  abort() { this.aborted = true; }
  addEventListener() {}
  send(body) {
    native('http',{method:this.method,url:this.url,headers:this.headers,body:body || ''}).then(r => {
      if (this.aborted) return;
      this.status=r.status;this.responseText=r.text;this.response=r.text;this.readyState=4;
      if(this.onload) this.onload(); if(this.onreadystatechange) this.onreadystatechange();
    }).catch(e => { if(this.onerror) this.onerror(e); });
  }
}
window.XMLHttpRequest = NativeXHR;
const listeners = {};
const socket = {
  on(e,f) { (listeners[e] ||= []).push(f); return this; },
  off(e,f) { listeners[e] = (listeners[e] || []).filter(x=>x!==f); return this; },
  emit(e, raw, cb) { native('socket',{event:e,raw}).then(cb).catch(e=>cb({code:500,message:String(e)})); }
};
window.deliver = (event, raw) => { for (const f of listeners[event] || []) f(raw); };
let apps = {};
window.configure = config => {
  const sdk = window.PolyvILSDK;
  sdk.Logger.disableUploadLog();
  sdk.setChatInfo({chat:socket,socketId:config.socketId,userId:'desktop-assistant'});
  sdk.setChannelInfo({channelId:config.channelId,roomId:config.roomId,sessionId:config.sessionId,channelType:'normal'});
  sdk.setAuthorization(()=>native('authorization',{}));
};
window.invoke = async (module, method, args) => {
  const app = apps[module] ||= new window.PolyvILSDK[module]();
  if(typeof app[method] !== 'function') throw Error('SDK 方法不可用');
  return (await app[method](...args)) ?? {success:true};
};
