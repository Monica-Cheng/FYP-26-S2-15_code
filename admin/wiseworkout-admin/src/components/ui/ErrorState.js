import React from 'react';
import { AlertCircle } from 'lucide-react';

function ErrorState({
  title = 'Something went wrong',
  message,
  onRetry,
  retryLabel = 'Try again',
  className = '',
}) {
  return (
    <div className={`wwa-error-state ${className}`.trim()} role="alert">
      <div className="wwa-error-state__icon">
        <AlertCircle aria-hidden="true" size={16} strokeWidth={2} />
      </div>
      <div className="wwa-error-state__content">
        <div className="wwa-error-state__title">{title}</div>
        {message ? <div className="wwa-error-state__message">{message}</div> : null}
      </div>
      {onRetry ? (
        <button type="button" className="wwa-btn wwa-btn-sm wwa-btn-secondary" onClick={onRetry}>
          {retryLabel}
        </button>
      ) : null}
    </div>
  );
}

export default ErrorState;
