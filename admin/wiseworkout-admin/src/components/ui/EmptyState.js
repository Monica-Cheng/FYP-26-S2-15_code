import React from 'react';

function EmptyState({ icon = '🗂️', title, message, className = '' }) {
  return (
    <div className={`wwa-empty ${className}`.trim()}>
      {icon ? <div className="wwa-empty-icon">{icon}</div> : null}
      {title && <div className="wwa-empty-title">{title}</div>}
      {message && <div>{message}</div>}
    </div>
  );
}

export default EmptyState;
