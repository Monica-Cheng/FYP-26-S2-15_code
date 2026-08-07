import React from 'react';

function EmptyState({ icon = '🗂️', title, message }) {
  return (
    <div className="wwa-empty">
      <div className="wwa-empty-icon">{icon}</div>
      {title && <div className="wwa-empty-title">{title}</div>}
      {message && <div>{message}</div>}
    </div>
  );
}

export default EmptyState;
