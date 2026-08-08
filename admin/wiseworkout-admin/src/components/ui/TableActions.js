import React, { useEffect, useRef, useState } from 'react';
import { MoreHorizontal } from 'lucide-react';

function TableActions({ items = [], label = 'Row actions', className = '' }) {
  const [open, setOpen] = useState(false);
  const containerRef = useRef(null);
  const triggerRef = useRef(null);

  useEffect(() => {
    if (!open) {
      return undefined;
    }

    const handlePointerDown = (event) => {
      if (!containerRef.current?.contains(event.target)) {
        setOpen(false);
      }
    };

    const handleKeyDown = (event) => {
      if (event.key === 'Escape') {
        setOpen(false);
        triggerRef.current?.focus();
      }
    };

    document.addEventListener('mousedown', handlePointerDown);
    document.addEventListener('keydown', handleKeyDown);

    return () => {
      document.removeEventListener('mousedown', handlePointerDown);
      document.removeEventListener('keydown', handleKeyDown);
    };
  }, [open]);

  const actionItems = items.filter(Boolean);

  return (
    <div className={`wwa-table-actions ${className}`.trim()} ref={containerRef}>
      <button
        ref={triggerRef}
        type="button"
        className="wwa-btn wwa-btn-icon wwa-btn-ghost wwa-table-actions__trigger"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label={label}
        onClick={() => setOpen((value) => !value)}
      >
        <MoreHorizontal aria-hidden="true" size={16} strokeWidth={2} />
      </button>

      {open ? (
        <div className="wwa-table-actions__menu" role="menu" aria-label={label}>
          {actionItems.map((item, index) => {
            if (item.type === 'divider') {
              return <div key={`divider-${index}`} className="wwa-table-actions__divider" role="separator" />;
            }

            return (
              <button
                key={item.key || item.label || index}
                type="button"
                role="menuitem"
                className={`wwa-table-actions__item ${item.tone === 'danger' ? 'is-danger' : ''}`}
                disabled={item.disabled}
                onClick={() => {
                  item.onSelect?.();
                  setOpen(false);
                }}
              >
                {item.icon ? <span className="wwa-table-actions__item-icon">{item.icon}</span> : null}
                <span>{item.label}</span>
              </button>
            );
          })}
        </div>
      ) : null}
    </div>
  );
}

export default TableActions;
