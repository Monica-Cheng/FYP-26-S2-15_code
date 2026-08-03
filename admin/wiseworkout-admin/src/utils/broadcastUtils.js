// adminBroadcasts only ever uses audience "all" and a boolean processed flag —
// this maps those exact backend values to the labels shown in the UI.
export function broadcastAudienceLabel(audience) {
  return audience === 'all' ? 'All Users' : (audience || '—');
}

export function broadcastStatusLabel(processed) {
  return processed === true ? 'Completed' : 'Queued';
}
