import React, { useId } from 'react';
import { Search, X } from 'lucide-react';

function SearchInput({
  value,
  onChange,
  placeholder = 'Search',
  label = 'Search',
  ariaLabel,
  onClear,
  className = '',
  inputClassName = '',
  ...inputProps
}) {
  const generatedId = useId();
  const inputId = inputProps.id || generatedId;
  const showClear = Boolean(onClear && value);

  return (
    <div className={`wwa-search-input ${className}`.trim()}>
      {label ? (
        <label className="wwa-visually-hidden" htmlFor={inputId}>
          {label}
        </label>
      ) : null}
      <Search className="wwa-search-input__icon" aria-hidden="true" strokeWidth={2} />
      <input
        {...inputProps}
        id={inputId}
        type="search"
        value={value}
        onChange={onChange}
        placeholder={placeholder}
        aria-label={ariaLabel || label}
        className={`wwa-input wwa-search-input__control ${inputClassName}`.trim()}
      />
      {showClear ? (
        <button
          type="button"
          className="wwa-search-input__clear"
          onClick={onClear}
          aria-label="Clear search"
        >
          <X aria-hidden="true" size={14} strokeWidth={2} />
        </button>
      ) : null}
    </div>
  );
}

export default SearchInput;
