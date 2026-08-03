import React from 'react';

// Shared dynamic list editor for a badge's `conditions` array — used by both
// the Add Badge form and BadgeDetailPanel's edit mode so the two stay in sync.
function ConditionsEditor({ conditions, onChange, disabled }) {
  const updateCondition = (index, field, value) => {
    onChange(conditions.map((c, i) => (i === index ? { ...c, [field]: value } : c)));
  };

  const addCondition = () => {
    onChange([...conditions, { statType: '', value: '' }]);
  };

  const removeCondition = (index) => {
    onChange(conditions.filter((_, i) => i !== index));
  };

  return (
    <div>
      <label className="wwa-field-label">Conditions</label>
      <div style={{ fontSize: 12, color: '#9ca3af', marginBottom: 10 }}>
        No stat types are read by the app yet — enter the exact key your badge-evaluation
        logic will expect (e.g. totalDistanceMeters).
      </div>
      {conditions.map((condition, index) => (
        <div key={index} style={{ display: 'flex', gap: 10, alignItems: 'flex-end', marginBottom: 10, flexWrap: 'wrap' }}>
          <div style={{ flex: 2, minWidth: 160 }}>
            {index === 0 && <label className="wwa-field-label">Stat Type</label>}
            <input
              className="wwa-input"
              value={condition.statType}
              onChange={e => updateCondition(index, 'statType', e.target.value)}
              placeholder="e.g. totalDistanceMeters"
              disabled={disabled}
            />
          </div>
          <div style={{ flex: 1, minWidth: 120 }}>
            {index === 0 && <label className="wwa-field-label">Value</label>}
            <input
              type="number"
              min="0"
              className="wwa-input"
              value={condition.value}
              onChange={e => updateCondition(index, 'value', e.target.value)}
              placeholder="e.g. 50000"
              disabled={disabled}
            />
          </div>
          <button
            type="button"
            className="wwa-btn wwa-btn-sm wwa-btn-danger"
            onClick={() => removeCondition(index)}
            disabled={disabled || conditions.length <= 1}
          >
            Remove
          </button>
        </div>
      ))}
      <button type="button" className="wwa-btn wwa-btn-sm wwa-btn-secondary" onClick={addCondition} disabled={disabled}>
        + Add Condition
      </button>
    </div>
  );
}

export default ConditionsEditor;
