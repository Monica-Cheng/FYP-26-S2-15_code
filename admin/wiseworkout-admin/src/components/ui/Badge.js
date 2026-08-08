import React from 'react';

function Badge({ tone = 'neutral', size = 'md', className = '', children }) {
  const classes = ['wwa-badge', `wwa-badge-${tone}`, size === 'sm' ? 'wwa-badge-sm' : '', className]
    .filter(Boolean)
    .join(' ');

  return <span className={classes}>{children}</span>;
}

export default Badge;
