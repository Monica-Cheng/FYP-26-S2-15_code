import React from 'react';

function Badge({ tone = 'neutral', children }) {
  return <span className={`wwa-badge wwa-badge-${tone}`}>{children}</span>;
}

export default Badge;
