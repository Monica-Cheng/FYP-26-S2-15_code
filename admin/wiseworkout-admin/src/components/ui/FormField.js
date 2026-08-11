import React, { useId } from 'react';

function FormField({
  label,
  labelFor,
  required = false,
  optional = false,
  helpText,
  error,
  children,
  className = '',
  fullWidth = false,
}) {
  const generatedId = useId();
  const fieldId = labelFor || generatedId;

  return (
    <div className={`wwa-form-field ${fullWidth ? 'wwa-form-field-full' : ''} ${className}`.trim()}>
      {label ? (
        <div className="wwa-form-field__label-row">
          <label className="wwa-form-field__label" htmlFor={fieldId}>
            {label}
          </label>
          {required ? <span className="wwa-form-field__meta">Required</span> : null}
          {!required && optional ? <span className="wwa-form-field__meta">Optional</span> : null}
        </div>
      ) : null}
      <div className="wwa-form-field__control">{children}</div>
      {helpText ? (
        <div id={`${fieldId}-help`} className="wwa-form-field__help">
          {helpText}
        </div>
      ) : null}
      {error ? (
        <div id={`${fieldId}-error`} className="wwa-form-field__error" role="alert">
          {error}
        </div>
      ) : null}
    </div>
  );
}

export default FormField;
