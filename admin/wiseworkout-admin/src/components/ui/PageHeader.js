import React from 'react';

function PageHeader({
  title,
  subtitle,
  description,
  meta,
  count,
  secondaryAction,
  primaryAction,
  actions,
  children,
  className = '',
}) {
  const supportingText = description || subtitle;
  const hasSplitActions = secondaryAction || primaryAction;
  const headerClassName = ['wwa-page-header', className].filter(Boolean).join(' ');

  return (
    <div className={headerClassName}>
      <div className="wwa-page-header__content">
        <h1 className="wwa-title">{title}</h1>
        {supportingText && <p className="wwa-subtitle">{supportingText}</p>}
        {(meta || count !== undefined) && (
          <div className="wwa-page-header__meta">
            {meta ? <span>{meta}</span> : null}
            {count !== undefined ? <span>{count}</span> : null}
          </div>
        )}
      </div>
      {(actions || hasSplitActions || children) && (
        <div className="wwa-header-actions">
          {actions || (
            <>
              {secondaryAction}
              {primaryAction}
              {children}
            </>
          )}
        </div>
      )}
    </div>
  );
}

export default PageHeader;
