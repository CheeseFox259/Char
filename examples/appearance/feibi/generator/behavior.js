// Events only. No timer, polling, navigation change, or automatic theme switch.
let hovering = false;
const states = new Map();
function onEvent(event) {
  if (event.name === 'select' || event.name === 'theme') { states.clear(); hovering = false; return []; }
  if (event.name === 'hoverEnter') { if (hovering) return []; hovering = true; return [{type:'playClip',value:'focus'}]; }
  if (event.name === 'hoverLeave') { if (!hovering) return []; hovering = false; return [{type:'playClip',value:'idle'}]; }
  if (event.name !== 'attention') return [];
  const key = event.workEnd || 'unknown';
  if (states.get(key) === event.state) return [];
  // Bounded memory for dynamic client identifiers.
  if (states.size >= 128 && !states.has(key)) states.delete(states.keys().next().value);
  states.set(key,event.state);
  const clip = {question:'curious',approval:'curious',failure:'concern',rateLimit:'concern',contextExhausted:'concern',turnEnded:'celebrate'}[event.state];
  return clip ? [{type:'playClip',value:clip}] : [];
}
