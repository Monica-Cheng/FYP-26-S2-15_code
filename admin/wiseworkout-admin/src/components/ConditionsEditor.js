import React from 'react';
import { Plus, Trash2 } from 'lucide-react';
import { FALLBACK_BADGE_STAT_TYPES } from '../utils/badgeUtils';

function ConditionsEditorStyles() {
  return (
    <style>{`
      .wwbc-editor {
        display: flex;
        flex-direction: column;
        gap: 14px;
      }
      .wwbc-editor__help {
        font-size: var(--ww-type-secondary-size);
        color: var(--ww-text-sec);
        line-height: 1.5;
      }
      .wwbc-editor__list {
        display: flex;
        flex-direction: column;
        gap: 14px;
      }
      .wwbc-editor__item {
        display: flex;
        flex-direction: column;
        gap: 12px;
        padding: 16px 0 0;
        border-top: 1px solid var(--ww-divider);
      }
      .wwbc-editor__item:first-child {
        padding-top: 0;
        border-top: 0;
      }
      .wwbc-editor__item-title {
        font-size: var(--ww-type-table-header-size);
        font-weight: var(--ww-type-table-header-weight);
        color: var(--ww-text-sec);
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }
      .wwbc-editor__grid {
        display: grid;
        grid-template-columns: minmax(0, 1.35fr) minmax(140px, 0.8fr) auto;
        gap: 12px;
        align-items: end;
      }
      .wwbc-editor__action {
        display: flex;
        justify-content: flex-start;
      }
      .wwbc-editor__footer {
        display: flex;
        justify-content: flex-start;
      }
      .wwbc-editor-stacked .wwbc-editor__grid {
        grid-template-columns: minmax(0, 1fr);
      }
      .wwbc-editor-stacked .wwbc-editor__action {
        margin-top: -2px;
      }
      @media (max-width: 900px) {
        .wwbc-editor__grid {
          grid-template-columns: minmax(0, 1fr);
        }
      }
    `}</style>
  );
}

function ConditionsEditor({ conditions, onChange, disabled, layout = 'default', supportedStatTypes }) {
  const statTypes = Array.isArray(supportedStatTypes) && supportedStatTypes.length > 0
    ? supportedStatTypes
    : FALLBACK_BADGE_STAT_TYPES;
  const selectedStatTypes = conditions
    .map((condition) => condition?.statType)
    .filter((value) => typeof value === 'string' && value.trim());

  const updateCondition = (index, field, value) => {
    onChange(conditions.map((condition, itemIndex) => (itemIndex === index ? { ...condition, [field]: value } : condition)));
  };

  const addCondition = () => {
    onChange([...conditions, { statType: '', value: '' }]);
  };

  const removeCondition = (index) => {
    onChange(conditions.filter((_, itemIndex) => itemIndex !== index));
  };

  return (
    <div className={`wwbc-editor ${layout === 'stacked' ? 'wwbc-editor-stacked' : ''}`.trim()}>
      <ConditionsEditorStyles />
      <label className="wwa-field-label">Earning Conditions</label>
      <div className="wwbc-editor__help">
        Choose one of the supported WiseWorkout statistics that the mobile app evaluates when awarding badges.
      </div>

      <div className="wwbc-editor__list">
        {conditions.map((condition, index) => (
          <div key={index} className="wwbc-editor__item">
            <div className="wwbc-editor__item-title">Condition {index + 1}</div>
            <div className="wwbc-editor__grid">
              <div>
                <label className="wwa-field-label" htmlFor={`badge-condition-stat-${index}`}>Stat Type</label>
                <select
                  id={`badge-condition-stat-${index}`}
                  className="wwa-select"
                  value={condition.statType}
                  onChange={(event) => updateCondition(index, 'statType', event.target.value)}
                  disabled={disabled}
                >
                  <option value="">Select stat type...</option>
                  {statTypes.map((type) => {
                    const selectedElsewhere = selectedStatTypes.includes(type) && condition.statType !== type;

                    return (
                      <option key={type} value={type} disabled={selectedElsewhere}>
                        {type}
                      </option>
                    );
                  })}
                </select>
              </div>

              <div>
                <label className="wwa-field-label" htmlFor={`badge-condition-value-${index}`}>Value</label>
                <input
                  id={`badge-condition-value-${index}`}
                  type="number"
                  min="0"
                  className="wwa-input"
                  value={condition.value}
                  onChange={(event) => updateCondition(index, 'value', event.target.value)}
                  placeholder="e.g. 50000"
                  disabled={disabled}
                />
              </div>

              <div className="wwbc-editor__action">
                <button
                  type="button"
                  className="wwa-btn wwa-btn-sm wwa-btn-danger"
                  onClick={() => removeCondition(index)}
                  disabled={disabled || conditions.length <= 1}
                  aria-label={`Remove condition ${index + 1}`}
                >
                  <Trash2 aria-hidden="true" size={14} strokeWidth={2} />
                  Remove
                </button>
              </div>
            </div>
          </div>
        ))}
      </div>

      <div className="wwbc-editor__footer">
        <button type="button" className="wwa-btn wwa-btn-sm wwa-btn-secondary" onClick={addCondition} disabled={disabled}>
          <Plus aria-hidden="true" size={14} strokeWidth={2} />
          Add Condition
        </button>
      </div>
    </div>
  );
}

export default ConditionsEditor;
