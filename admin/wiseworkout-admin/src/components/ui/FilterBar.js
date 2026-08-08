import React from 'react';

function FilterBar({
  search,
  filters,
  onReset,
  resetLabel = 'Reset',
  resetDisabled = false,
  exportAction,
  count,
  rightContent,
  leftContent,
  className = '',
}) {
  return (
    <div className={`wwa-filterbar ${className}`.trim()}>
      <div className="wwa-filterbar__left">
        {search ? <div className="wwa-filterbar__search">{search}</div> : null}
        {filters ? <div className="wwa-filterbar__filters">{filters}</div> : null}
        {onReset ? (
          <button type="button" className="wwa-btn wwa-btn-sm wwa-btn-ghost" onClick={onReset} disabled={resetDisabled}>
            {resetLabel}
          </button>
        ) : null}
        {leftContent}
      </div>
      <div className="wwa-filterbar__right">
        {count !== undefined && count !== null ? <div className="wwa-filterbar__count">{count}</div> : null}
        {rightContent}
        {exportAction}
      </div>
    </div>
  );
}

export default FilterBar;
