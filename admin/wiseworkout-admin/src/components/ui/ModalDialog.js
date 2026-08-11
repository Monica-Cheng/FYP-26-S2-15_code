import React, { useEffect } from 'react';
import { X } from 'lucide-react';

function ModalDialog({
  open = false,
  title,
  description,
  size = 'md',
  footer,
  onClose,
  closeOnBackdrop = true,
  children,
}) {
  useEffect(() => {
    if (!open) {
      return undefined;
    }

    const handleKeyDown = (event) => {
      if (event.key === 'Escape') {
        onClose?.();
      }
    };

    document.addEventListener('keydown', handleKeyDown);

    return () => {
      document.removeEventListener('keydown', handleKeyDown);
    };
  }, [open, onClose]);

  if (!open) {
    return null;
  }

  return (
    <div
      className="wwa-modal"
      role="presentation"
      onMouseDown={(event) => {
        if (closeOnBackdrop && event.target === event.currentTarget) {
          onClose?.();
        }
      }}
    >
      <div
        className={`wwa-modal__panel ${size === 'lg' ? 'wwa-modal__panel-lg' : ''} ${size === 'xl' ? 'wwa-modal__panel-xl' : ''}`.trim()}
        role="dialog"
        aria-modal="true"
        aria-label={title || 'Dialog'}
      >
        <div className="wwa-modal__header">
          <div className="wwa-modal__header-main">
            {title ? <h2 className="wwa-modal__title">{title}</h2> : null}
            {description ? <p className="wwa-modal__description">{description}</p> : null}
          </div>
          {onClose ? (
            <button type="button" className="wwa-panel-close" onClick={onClose} aria-label="Close dialog">
              <X aria-hidden="true" size={16} strokeWidth={2} />
            </button>
          ) : null}
        </div>
        <div className="wwa-modal__body">{children}</div>
        {footer ? <div className="wwa-modal__footer">{footer}</div> : null}
      </div>
    </div>
  );
}

export default ModalDialog;
