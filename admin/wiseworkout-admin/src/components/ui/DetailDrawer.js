import React from 'react';
import { X } from 'lucide-react';

function DetailDrawer({
  open = true,
  width = 'default',
  title,
  actions,
  summary,
  footer,
  onClose,
  children,
  className = '',
}) {
  if (!open) {
    return null;
  }

  return (
    <aside
      className={`wwa-detail-drawer ${width === 'wide' ? 'wwa-detail-drawer-wide' : ''} ${className}`.trim()}
      role="dialog"
      aria-modal="false"
      aria-label={title || 'Detail drawer'}
    >
      <div className="wwa-detail-drawer__header">
        <div className="wwa-detail-drawer__header-main">
          {title ? <h2 className="wwa-detail-drawer__title">{title}</h2> : null}
          {actions ? <div className="wwa-detail-drawer__header-actions">{actions}</div> : null}
        </div>
        {onClose ? (
          <button type="button" className="wwa-panel-close" onClick={onClose} aria-label="Close panel">
            <X aria-hidden="true" size={16} strokeWidth={2} />
          </button>
        ) : null}
      </div>
      {summary ? <div className="wwa-detail-drawer__summary">{summary}</div> : null}
      <div className="wwa-detail-drawer__body">{children}</div>
      {footer ? <div className="wwa-detail-drawer__footer">{footer}</div> : null}
    </aside>
  );
}

export default DetailDrawer;
