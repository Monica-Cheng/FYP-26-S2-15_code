import React, { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { MoreHorizontal } from 'lucide-react';

function TableActions({ items = [], label = 'Row actions', className = '' }) {
  const [open, setOpen] = useState(false);
  const [menuStyle, setMenuStyle] = useState(null);
  const containerRef = useRef(null);
  const triggerRef = useRef(null);
  const menuRef = useRef(null);

  useEffect(() => {
    if (!open) {
      return undefined;
    }

    const handlePointerDown = (event) => {
      if (!containerRef.current?.contains(event.target) && !menuRef.current?.contains(event.target)) {
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

  useLayoutEffect(() => {
    if (!open || !triggerRef.current || !menuRef.current) {
      return undefined;
    }

    const positionMenu = () => {
      const triggerRect = triggerRef.current.getBoundingClientRect();
      const menuRect = menuRef.current.getBoundingClientRect();
      const viewportWidth = window.innerWidth;
      const viewportHeight = window.innerHeight;
      const gap = 8;

      let left = triggerRect.right - menuRect.width;
      if (left < gap) {
        left = gap;
      }
      if (left + menuRect.width > viewportWidth - gap) {
        left = Math.max(gap, viewportWidth - menuRect.width - gap);
      }

      let top = triggerRect.bottom + gap;
      let originY = 'top';
      if (top + menuRect.height > viewportHeight - gap) {
        top = triggerRect.top - menuRect.height - gap;
        originY = 'bottom';
      }
      if (top < gap) {
        top = Math.max(gap, Math.min(triggerRect.bottom + gap, viewportHeight - menuRect.height - gap));
        originY = 'top';
      }

      setMenuStyle({
        position: 'fixed',
        top,
        left,
        zIndex: 1400,
        transformOrigin: `${originY} right`,
      });
    };

    positionMenu();
    window.addEventListener('resize', positionMenu);
    window.addEventListener('scroll', positionMenu, true);

    return () => {
      window.removeEventListener('resize', positionMenu);
      window.removeEventListener('scroll', positionMenu, true);
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

      {open ? createPortal(
        <div ref={menuRef} className="wwa-table-actions__menu" role="menu" aria-label={label} style={menuStyle || undefined}>
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
                onClick={(event) => {
                  event.stopPropagation();
                  item.onSelect?.();
                  setOpen(false);
                }}
              >
                {item.icon ? <span className="wwa-table-actions__item-icon">{item.icon}</span> : null}
                <span>{item.label}</span>
              </button>
            );
          })}
        </div>,
        document.body
      ) : null}
    </div>
  );
}

export default TableActions;
