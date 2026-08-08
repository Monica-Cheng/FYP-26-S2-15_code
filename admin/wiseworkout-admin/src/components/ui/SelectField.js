import React, { useId } from 'react';
import { ChevronDown } from 'lucide-react';
import FormField from './FormField';

function SelectField({
  options = [],
  label,
  helpText,
  error,
  required = false,
  optional = false,
  className = '',
  selectClassName = '',
  fullWidth = false,
  placeholder,
  ...selectProps
}) {
  const generatedId = useId();
  const selectId = selectProps.id || generatedId;
  const hasFieldWrapper = Boolean(label || helpText || error || required || optional);
  const describedBy = [
    helpText ? `${selectId}-help` : null,
    error ? `${selectId}-error` : null,
  ]
    .filter(Boolean)
    .join(' ') || undefined;

  const content = (
    <div className={`wwa-select-field ${className}`.trim()}>
      <select
        {...selectProps}
        id={selectId}
        aria-invalid={error ? true : selectProps['aria-invalid']}
        aria-describedby={[selectProps['aria-describedby'], describedBy].filter(Boolean).join(' ') || undefined}
        className={`wwa-select wwa-select-field__control ${selectClassName}`.trim()}
      >
        {placeholder ? <option value="">{placeholder}</option> : null}
        {options.map((option) => {
          if (typeof option === 'string') {
            return (
              <option key={option} value={option}>
                {option}
              </option>
            );
          }

          return (
            <option key={option.value} value={option.value} disabled={option.disabled}>
              {option.label}
            </option>
          );
        })}
      </select>
      <ChevronDown className="wwa-select-field__icon" aria-hidden="true" size={16} strokeWidth={2} />
    </div>
  );

  if (!hasFieldWrapper) {
    return content;
  }

  return (
    <FormField
      label={label}
      labelFor={selectId}
      helpText={helpText}
      error={error}
      required={required}
      optional={optional}
      fullWidth={fullWidth}
    >
      {content}
    </FormField>
  );
}

export default SelectField;
