import React from 'react';

function PageHeader({ title, subtitle, actions }) {
  return (
    <div className="wwa-page-header">
      <div>
        <h1 className="wwa-title">{title}</h1>
        {subtitle && <p className="wwa-subtitle">{subtitle}</p>}
      </div>
      {actions && <div className="wwa-header-actions">{actions}</div>}
    </div>
  );
}

export default PageHeader;
