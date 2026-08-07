import React from 'react';

// Shared visual language for every admin page (except the Dashboard, which
// keeps its own scoped styles). Mirrors the palette, radii, shadows and
// spacing established on the Dashboard so every page reads as one system.
// Purely presentational — no logic, no data.
export const COLORS = {
  primary: { base: '#6c63ff', light: '#eef0ff' },
  cyan: { base: '#48cae4', light: '#e8f8fb' },
  green: { base: '#06d6a0', light: '#e5fbf3' },
  red: { base: '#ff6b6b', light: '#ffeded' },
  amber: { base: '#ffd166', light: '#fff6df' },
};

function AdminStyles() {
  return (
    <style>{`
      .wwa-page-header {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        flex-wrap: wrap;
        gap: 16px;
        margin-bottom: 26px;
      }
      .wwa-title {
        font-size: 26px;
        font-weight: 800;
        color: #111827;
        letter-spacing: -0.02em;
        margin-bottom: 6px;
      }
      .wwa-subtitle { color: #9ca3af; font-size: 14px; }
      .wwa-header-actions { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }

      .wwa-toolbar { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; margin-bottom: 20px; }
      .wwa-search { flex: 1; min-width: 220px; }

      .wwa-input, .wwa-select, .wwa-search input {
        width: 100%;
        padding: 10px 14px;
        border-radius: 10px;
        border: 1px solid #e5e7eb;
        font-size: 14px;
        outline: none;
        font-family: inherit;
        color: #111827;
        background: #ffffff;
        transition: border-color 0.15s ease, box-shadow 0.15s ease;
      }
      .wwa-input:focus, .wwa-select:focus, .wwa-search input:focus {
        border-color: #6c63ff;
        box-shadow: 0 0 0 3px rgba(108, 99, 255, 0.12);
      }
      .wwa-input::placeholder { color: #b0b3bd; }
      .wwa-input-sm { width: 110px; text-align: right; padding: 8px 12px; }

      .wwa-pill-group { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 20px; }
      .wwa-pill {
        padding: 8px 16px;
        border-radius: 999px;
        font-size: 13px;
        font-weight: 600;
        border: 1px solid #e5e7eb;
        background: #ffffff;
        color: #6b7280;
        cursor: pointer;
        font-family: inherit;
        transition: all 0.15s ease;
      }
      .wwa-pill:hover { border-color: #6c63ff; color: #6c63ff; }
      .wwa-pill-active, .wwa-pill-active:hover { background: #6c63ff; border-color: #6c63ff; color: #ffffff; }

      .wwa-select-inline { width: auto; min-width: 150px; flex: 0 0 auto; }
      .wwa-toolbar-count { font-size: 13px; color: #9ca3af; white-space: nowrap; }

      .wwa-panel {
        background: #ffffff;
        border-radius: 16px;
        padding: 24px;
        border: 1px solid #eef0f4;
        box-shadow: 0 1px 2px rgba(16, 24, 40, 0.04);
        margin-bottom: 24px;
      }
      .wwa-panel:last-child { margin-bottom: 0; }
      .wwa-panel-title { font-size: 16px; font-weight: 700; color: #111827; margin-bottom: 4px; }
      .wwa-panel-subtitle { font-size: 13px; color: #9ca3af; margin-bottom: 18px; }

      .wwa-table-wrap {
        background: #ffffff;
        border-radius: 16px;
        border: 1px solid #eef0f4;
        box-shadow: 0 1px 2px rgba(16, 24, 40, 0.04);
        overflow: hidden;
        overflow-x: auto;
      }
      .wwa-table { width: 100%; border-collapse: collapse; font-size: 14px; min-width: 640px; }
      .wwa-table thead tr { background: #f9fafb; border-bottom: 1px solid #eef0f4; }
      .wwa-table th {
        padding: 14px 18px;
        text-align: left;
        font-weight: 700;
        color: #6b7280;
        font-size: 12.5px;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        white-space: nowrap;
      }
      .wwa-table td { padding: 14px 18px; border-bottom: 1px solid #f3f4f6; color: #374151; vertical-align: middle; }
      .wwa-table tbody tr { transition: background 0.12s ease; }
      .wwa-table tbody tr:hover { background: #fafafe; }
      .wwa-table tbody tr:last-child td { border-bottom: none; }
      .wwa-cell-primary { font-weight: 600; color: #111827; }
      .wwa-cell-muted { color: #9ca3af; font-size: 12px; margin-top: 2px; }
      .wwa-cell-actions { display: flex; gap: 8px; flex-wrap: wrap; }

      .wwa-row-card {
        background: #ffffff;
        border-radius: 14px;
        padding: 18px 20px;
        border: 1px solid #eef0f4;
        box-shadow: 0 1px 2px rgba(16, 24, 40, 0.04);
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 16px;
        flex-wrap: wrap;
        transition: box-shadow 0.15s ease;
        margin-bottom: 12px;
      }
      .wwa-row-card:last-child { margin-bottom: 0; }
      .wwa-row-card:hover { box-shadow: 0 8px 20px rgba(16, 24, 40, 0.06); }
      .wwa-row-title { font-weight: 700; font-size: 15px; color: #111827; }
      .wwa-row-sub { font-size: 13px; color: #9ca3af; margin-top: 4px; }
      .wwa-row-meta { font-size: 12px; color: #b5b8c0; margin-top: 4px; }
      .wwa-row-actions { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
      .wwa-row-list { display: flex; flex-direction: column; }

      .wwa-btn {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 8px;
        padding: 10px 20px;
        border-radius: 10px;
        border: none;
        font-size: 14px;
        font-weight: 600;
        cursor: pointer;
        font-family: inherit;
        transition: transform 0.12s ease, box-shadow 0.12s ease, opacity 0.12s ease, background 0.12s ease;
        white-space: nowrap;
      }
      .wwa-btn:hover { transform: translateY(-1px); box-shadow: 0 6px 14px rgba(16, 24, 40, 0.12); }
      .wwa-btn:disabled { opacity: 0.6; cursor: not-allowed; transform: none; box-shadow: none; }
      .wwa-btn-sm { padding: 7px 14px; border-radius: 8px; font-size: 12.5px; }
      .wwa-btn-primary { background: #6c63ff; color: #ffffff; }
      .wwa-btn-success { background: #06d6a0; color: #ffffff; }
      .wwa-btn-danger-solid { background: #ff6b6b; color: #ffffff; }
      .wwa-btn-secondary { background: #ffffff; color: #374151; border: 1px solid #e5e7eb; }
      .wwa-btn-secondary:hover { border-color: #c7c9d1; }
      .wwa-btn-danger { background: #fff0f0; color: #cc3333; }
      .wwa-btn-success-soft { background: #e6f9f0; color: #1a9e6a; }
      .wwa-btn-brand-soft { background: #f0f0ff; color: #6c63ff; }

      .wwa-empty { text-align: center; padding: 56px 24px; color: #9ca3af; font-size: 14px; }
      .wwa-empty-icon { font-size: 30px; margin-bottom: 10px; opacity: 0.6; }
      .wwa-empty-title { font-weight: 600; color: #6b7280; margin-bottom: 4px; font-size: 14px; }

      .wwa-skeleton {
        border-radius: 16px;
        background: linear-gradient(90deg, #eef0f4 25%, #f7f8fa 37%, #eef0f4 63%);
        background-size: 400% 100%;
        animation: wwa-shimmer 1.4s ease infinite;
      }
      @keyframes wwa-shimmer {
        0% { background-position: 100% 50%; }
        100% { background-position: 0 50%; }
      }

      .wwa-status-pill {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        font-size: 13px;
        font-weight: 600;
        color: #06a97e;
        background: #e5fbf3;
        padding: 6px 12px;
        border-radius: 999px;
        white-space: nowrap;
      }
      .wwa-status-dot { width: 6px; height: 6px; border-radius: 50%; background: #06d6a0; }

      .wwa-alert-error {
        background: #fff0f0;
        color: #cc0000;
        padding: 10px 14px;
        border-radius: 10px;
        font-size: 13px;
        font-weight: 500;
      }

      .wwa-badge {
        display: inline-flex;
        align-items: center;
        padding: 3px 12px;
        border-radius: 999px;
        font-size: 12px;
        font-weight: 600;
        line-height: 1.6;
        white-space: nowrap;
      }
      .wwa-badge-success { background: #e6f9f0; color: #1a9e6a; }
      .wwa-badge-danger { background: #fff0f0; color: #cc3333; }
      .wwa-badge-warning { background: #fff8e6; color: #cc8800; }
      .wwa-badge-brand { background: #f0f0ff; color: #6c63ff; }
      .wwa-badge-neutral { background: #f3f4f6; color: #6b7280; }

      .wwa-switch { position: relative; display: inline-block; width: 42px; height: 24px; flex-shrink: 0; }
      .wwa-switch input { opacity: 0; width: 0; height: 0; position: absolute; }
      .wwa-switch-track { position: absolute; inset: 0; background: #e5e7eb; border-radius: 999px; transition: background 0.15s ease; cursor: pointer; }
      .wwa-switch-track::before {
        content: '';
        position: absolute;
        width: 18px;
        height: 18px;
        left: 3px;
        top: 3px;
        background: #ffffff;
        border-radius: 50%;
        transition: transform 0.15s ease;
        box-shadow: 0 1px 2px rgba(0, 0, 0, 0.15);
      }
      .wwa-switch input:checked + .wwa-switch-track { background: #6c63ff; }
      .wwa-switch input:checked + .wwa-switch-track::before { transform: translateX(18px); }
      .wwa-switch input:focus-visible + .wwa-switch-track { box-shadow: 0 0 0 3px rgba(108, 99, 255, 0.25); }
      .wwa-switch input:disabled + .wwa-switch-track { opacity: 0.5; cursor: not-allowed; }

      .wwa-setting-row {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 16px 0;
        border-bottom: 1px solid #f3f4f6;
        gap: 16px;
        flex-wrap: wrap;
      }
      .wwa-setting-row:last-child { border-bottom: none; }
      .wwa-setting-label { font-size: 14px; font-weight: 600; color: #111827; }
      .wwa-setting-sub { font-size: 12.5px; color: #9ca3af; margin-top: 2px; }

      .wwa-form-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
        gap: 14px;
        margin-bottom: 16px;
      }
      .wwa-field-label { font-size: 13px; font-weight: 600; color: #4b5563; display: block; margin-bottom: 6px; }
      .wwa-field-full { grid-column: 1 / -1; }

      .wwa-stats-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
        gap: 20px;
      }
      .wwa-stat-card {
        background: #ffffff;
        border-radius: 16px;
        padding: 20px 22px;
        border: 1px solid #eef0f4;
        border-top: 3px solid var(--accent);
        box-shadow: 0 1px 2px rgba(16, 24, 40, 0.04);
        display: flex;
        flex-direction: column;
        gap: 8px;
        transition: transform 0.15s ease, box-shadow 0.15s ease;
      }
      .wwa-stat-card:hover { transform: translateY(-3px); box-shadow: 0 10px 24px rgba(16, 24, 40, 0.08); }
      .wwa-stat-top { display: flex; align-items: center; justify-content: space-between; }
      .wwa-stat-title {
        font-size: 12px;
        font-weight: 700;
        color: #6b7280;
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }
      .wwa-stat-icon {
        width: 32px;
        height: 32px;
        border-radius: 9px;
        background: var(--accent-light);
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 15px;
        flex-shrink: 0;
      }
      .wwa-stat-value { font-size: 26px; font-weight: 700; color: #111827; line-height: 1; }

      .wwa-table tbody tr.wwa-row-selected { background: #f5f4ff; }
      .wwa-table tbody tr.wwa-row-selected:hover { background: #f0efff; }

      .wwa-split-layout { display: flex; gap: 24px; align-items: flex-start; }
      .wwa-split-main { flex: 1; min-width: 0; }
      .wwa-split-side { width: 360px; flex-shrink: 0; }
      .wwa-split-side-wide { width: 460px; }

      .wwa-panel-close {
        width: 28px;
        height: 28px;
        border-radius: 8px;
        border: none;
        background: #f3f4f6;
        color: #6b7280;
        font-size: 14px;
        line-height: 1;
        cursor: pointer;
        display: flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
        font-family: inherit;
        transition: background 0.15s ease, color 0.15s ease;
      }
      .wwa-panel-close:hover { background: #ffeded; color: #cc3333; }

      .wwa-avatar {
        width: 52px;
        height: 52px;
        border-radius: 50%;
        background: #6c63ff;
        color: #ffffff;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 19px;
        font-weight: 700;
        flex-shrink: 0;
      }

      .wwa-detail-row {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 10px 0;
        border-bottom: 1px solid #f3f4f6;
        gap: 12px;
      }
      .wwa-detail-row:last-child { border-bottom: none; }
      .wwa-detail-label {
        font-size: 12px;
        color: #9ca3af;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        white-space: nowrap;
      }
      .wwa-detail-value { font-size: 13.5px; color: #111827; font-weight: 600; text-align: right; }

      .wwa-charts-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
        gap: 20px;
        margin-top: 20px;
      }
      .wwa-chart-card {
        background: #ffffff;
        border-radius: 16px;
        padding: 20px 22px;
        border: 1px solid #eef0f4;
        box-shadow: 0 1px 2px rgba(16, 24, 40, 0.04);
      }
      .wwa-chart-title { font-size: 14px; font-weight: 700; color: #111827; margin-bottom: 16px; }
      .wwa-chart-body { display: flex; align-items: center; gap: 20px; flex-wrap: wrap; }
      .wwa-chart-center-value { font-size: 22px; font-weight: 700; fill: #111827; font-family: inherit; }
      .wwa-chart-center-label {
        font-size: 10px; font-weight: 700; fill: #9ca3af; text-transform: uppercase;
        letter-spacing: 0.05em; font-family: inherit;
      }
      .wwa-chart-legend { display: flex; flex-direction: column; gap: 10px; flex: 1; min-width: 140px; }
      .wwa-chart-legend-row { display: flex; align-items: center; gap: 8px; font-size: 13px; }
      .wwa-chart-swatch { width: 10px; height: 10px; border-radius: 3px; flex-shrink: 0; }
      .wwa-chart-legend-label { color: #4b5563; flex: 1; }
      .wwa-chart-legend-value { color: #111827; font-weight: 700; white-space: nowrap; }

      .wwa-bar-chart {
        display: flex;
        align-items: flex-end;
        gap: 14px;
        height: 160px;
        padding-top: 20px;
      }
      .wwa-bar-col { display: flex; flex-direction: column; align-items: center; gap: 6px; height: 100%; }
      .wwa-bar-value { font-size: 12px; font-weight: 700; color: #111827; }
      .wwa-bar-track {
        width: 28px;
        flex: 1;
        background: #f3f4f6;
        border-radius: 6px;
        display: flex;
        align-items: flex-end;
        overflow: hidden;
      }
      .wwa-bar-fill { width: 100%; border-radius: 4px 4px 0 0; transition: height 0.2s ease; }
      .wwa-bar-label { font-size: 11px; color: #9ca3af; font-weight: 600; }

      .wwa-stat-sub { font-size: 11px; color: #9ca3af; font-weight: 600; margin-top: -2px; }

      .wwa-insights-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
        gap: 20px;
        margin-top: 20px;
      }
      .wwa-insight-row {
        display: flex;
        align-items: flex-start;
        gap: 10px;
        padding: 10px 0;
        border-bottom: 1px solid #f3f4f6;
        font-size: 13.5px;
        color: #374151;
        line-height: 1.4;
      }
      .wwa-insight-row:last-child { border-bottom: none; }
      .wwa-insight-icon { flex-shrink: 0; font-size: 14px; }

      .wwa-attention-panel { border-top: 3px solid #ff6b6b; }
      .wwa-attention-row {
        padding: 10px 0;
        border-bottom: 1px solid #fff0f0;
        font-size: 13.5px;
        color: #7a2323;
        line-height: 1.4;
      }
      .wwa-attention-row:last-child { border-bottom: none; }

      .wwa-recent-row {
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 10px 0;
        border-bottom: 1px solid #f3f4f6;
        font-size: 13px;
      }
      .wwa-recent-row:last-child { border-bottom: none; }
      .wwa-recent-icon { font-size: 14px; flex-shrink: 0; }
      .wwa-recent-text { color: #374151; flex: 1; min-width: 0; }
      .wwa-recent-date { color: #9ca3af; font-size: 12px; white-space: nowrap; flex-shrink: 0; }

      .wwa-session-card {
        border: 1px solid #eef0f4;
        border-radius: 12px;
        padding: 12px 14px;
        margin-bottom: 10px;
      }
      .wwa-session-header {
        display: flex;
        align-items: center;
        gap: 8px;
        flex-wrap: wrap;
        font-weight: 700;
        font-size: 13px;
        color: #111827;
        margin-bottom: 8px;
      }
      .wwa-exercise-row { padding: 8px 0; border-top: 1px solid #f3f4f6; }
      .wwa-exercise-row:first-child { border-top: none; }
      .wwa-exercise-name {
        display: flex;
        align-items: center;
        gap: 6px;
        font-size: 13px;
        font-weight: 600;
        color: #111827;
      }
      .wwa-exercise-meta { font-size: 11.5px; color: #9ca3af; margin-top: 2px; }
      .wwa-exercise-note { font-size: 11.5px; color: #6b7280; font-style: italic; margin-top: 2px; }
      .wwa-set-list { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 6px; }
      .wwa-set-chip {
        font-size: 11px;
        background: #f3f4f6;
        color: #374151;
        padding: 3px 8px;
        border-radius: 6px;
        font-weight: 600;
      }

      @media (max-width: 640px) {
        .wwa-row-card { flex-direction: column; align-items: flex-start; }
        .wwa-row-actions { width: 100%; }
        .wwa-table { min-width: 560px; }
        .wwa-recent-row { flex-wrap: wrap; }
        .wwa-recent-date { margin-left: 26px; }
      }
      @media (max-width: 900px) {
        .wwa-split-layout { flex-direction: column; }
        .wwa-split-side, .wwa-split-side-wide { width: 100%; }
      }
      @media (max-width: 480px) {
        .wwa-title { font-size: 22px; }
        .wwa-panel { padding: 18px; }
      }
    `}</style>
  );
}

export default AdminStyles;
