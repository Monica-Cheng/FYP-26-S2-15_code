import React from 'react';

function FormSection({
  title,
  description,
  children,
  columns = 2,
  className = '',
  contentClassName = '',
}) {
  const columnClass = columns === 1 ? 'wwa-form-section__content-one' : 'wwa-form-section__content-two';

  return (
    <section className={`wwa-form-section ${className}`.trim()}>
      {(title || description) ? (
        <header className="wwa-form-section__header">
          {title ? <h2 className="wwa-form-section__title">{title}</h2> : null}
          {description ? <p className="wwa-form-section__description">{description}</p> : null}
        </header>
      ) : null}
      <div className={`wwa-form-section__content ${columnClass} ${contentClassName}`.trim()}>
        {children}
      </div>
    </section>
  );
}

export default FormSection;
