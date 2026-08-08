import React from 'react';
import SkeletonBlock from './SkeletonBlock';

function LoadingState({
  title = 'Loading',
  message,
  rows = 0,
  className = '',
}) {
  if (rows > 0) {
    return (
      <div className={`wwa-loading-state ${className}`.trim()} aria-live="polite" aria-busy="true">
        <div className="wwa-loading-state__rows">
          {Array.from({ length: rows }).map((_, index) => (
            <SkeletonBlock key={index} height={44} className="wwa-loading-state__row" />
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className={`wwa-loading-state ${className}`.trim()} aria-live="polite" aria-busy="true">
      <div className="wwa-loading-state__title">{title}</div>
      {message ? <div className="wwa-loading-state__message">{message}</div> : null}
    </div>
  );
}

export default LoadingState;
