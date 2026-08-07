import React from 'react';

// Visual wrapper only — forwards checked/onChange to a real checkbox input
// so existing state logic in callers is untouched.
function ToggleSwitch({ checked, onChange, disabled = false }) {
  return (
    <label className="wwa-switch">
      <input type="checkbox" checked={checked} onChange={onChange} disabled={disabled} />
      <span className="wwa-switch-track" />
    </label>
  );
}

export default ToggleSwitch;
