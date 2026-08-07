import React, { useState, useEffect } from 'react';
import { functions } from '../firebase';
import { httpsCallable } from 'firebase/functions';
import { toDate, formatDate } from '../utils/dateUtils';

// Shared color palette for this page — keeps stat cards, icons and
// quick-action tiles visually consistent with each other.
const COLORS = {
  primary: { base: '#6c63ff', light: '#eef0ff' },
  cyan: { base: '#48cae4', light: '#e8f8fb' },
  green: { base: '#06d6a0', light: '#e5fbf3' },
  red: { base: '#ff6b6b', light: '#ffeded' },
  amber: { base: '#ffd166', light: '#fff6df' },
};

function DashboardStyles() {
  return (
    <style>{`
      .wwdash-header-row {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        flex-wrap: wrap;
        gap: 12px;
        margin-bottom: 28px;
      }
      .wwdash-title {
        font-size: 26px;
        font-weight: 800;
        color: #111827;
        letter-spacing: -0.02em;
        margin-bottom: 6px;
      }
      .wwdash-subtitle {
        color: #9ca3af;
        font-size: 14px;
      }
      .wwdash-live-pill {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        font-size: 12px;
        font-weight: 600;
        color: #06a97e;
        background: #e5fbf3;
        padding: 6px 12px;
        border-radius: 999px;
        white-space: nowrap;
      }
      .wwdash-live-dot {
        width: 6px;
        height: 6px;
        border-radius: 50%;
        background: #06d6a0;
        box-shadow: 0 0 0 0 rgba(6, 214, 160, 0.5);
        animation: wwdash-pulse 1.8s infinite;
      }
      @keyframes wwdash-pulse {
        0% { box-shadow: 0 0 0 0 rgba(6, 214, 160, 0.5); }
        70% { box-shadow: 0 0 0 6px rgba(6, 214, 160, 0); }
        100% { box-shadow: 0 0 0 0 rgba(6, 214, 160, 0); }
      }

      .wwdash-stats-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(230px, 1fr));
        gap: 20px;
        margin-bottom: 28px;
      }
      .wwdash-stat-card {
        background: #ffffff;
        border-radius: 16px;
        padding: 22px 24px;
        border: 1px solid #eef0f4;
        border-top: 3px solid var(--accent);
        box-shadow: 0 1px 2px rgba(16, 24, 40, 0.04);
        transition: transform 0.15s ease, box-shadow 0.15s ease;
        display: flex;
        flex-direction: column;
        gap: 10px;
      }
      .wwdash-stat-card:hover {
        transform: translateY(-3px);
        box-shadow: 0 10px 24px rgba(16, 24, 40, 0.08);
      }
      .wwdash-stat-top {
        display: flex;
        align-items: center;
        justify-content: space-between;
      }
      .wwdash-stat-title {
        font-size: 12.5px;
        font-weight: 700;
        color: #6b7280;
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }
      .wwdash-stat-icon {
        width: 36px;
        height: 36px;
        border-radius: 10px;
        background: var(--accent-light);
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 16px;
        flex-shrink: 0;
      }
      .wwdash-stat-value {
        font-size: 30px;
        font-weight: 700;
        color: #111827;
        line-height: 1;
      }
      .wwdash-stat-sub {
        font-size: 13px;
        color: #9ca3af;
      }

      .wwdash-panel {
        background: #ffffff;
        border-radius: 16px;
        padding: 24px;
        border: 1px solid #eef0f4;
        box-shadow: 0 1px 2px rgba(16, 24, 40, 0.04);
      }
      .wwdash-panel-title {
        font-size: 16px;
        font-weight: 700;
        color: #111827;
      }
      .wwdash-panel-subtitle {
        font-size: 13px;
        color: #9ca3af;
        margin-top: 2px;
        margin-bottom: 18px;
      }
      .wwdash-actions-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(210px, 1fr));
        gap: 12px;
      }
      .wwdash-action {
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 14px 16px;
        border-radius: 12px;
        border: 1px solid #eef0f4;
        background: #fafafe;
        color: #1f2937;
        font-size: 14px;
        font-weight: 600;
        font-family: inherit;
        cursor: pointer;
        text-align: left;
        transition: transform 0.15s ease, box-shadow 0.15s ease, background 0.15s ease, color 0.15s ease, border-color 0.15s ease;
      }
      .wwdash-action:hover {
        border-color: var(--accent);
        background: var(--accent-light);
        color: var(--accent);
        transform: translateY(-2px);
        box-shadow: 0 8px 18px rgba(16, 24, 40, 0.08);
      }
      .wwdash-action-icon {
        width: 34px;
        height: 34px;
        border-radius: 9px;
        background: var(--accent-light);
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 16px;
        flex-shrink: 0;
      }

      .wwdash-skeleton-card {
        border-radius: 16px;
        height: 128px;
        background: linear-gradient(90deg, #eef0f4 25%, #f7f8fa 37%, #eef0f4 63%);
        background-size: 400% 100%;
        animation: wwdash-shimmer 1.4s ease infinite;
      }
      .wwdash-skeleton-panel {
        border-radius: 16px;
        height: 160px;
        background: linear-gradient(90deg, #eef0f4 25%, #f7f8fa 37%, #eef0f4 63%);
        background-size: 400% 100%;
        animation: wwdash-shimmer 1.4s ease infinite;
      }
      @keyframes wwdash-shimmer {
        0% { background-position: 100% 50%; }
        100% { background-position: 0 50%; }
      }

      .wwdash-alert-item {
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 12px 0;
        border-bottom: 1px solid #f3f4f6;
      }
      .wwdash-alert-item:last-child { border-bottom: none; }
      .wwdash-alert-icon {
        width: 36px;
        height: 36px;
        border-radius: 10px;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 16px;
        flex-shrink: 0;
      }
      .wwdash-alert-icon-warning { background: #fff8e6; }
      .wwdash-alert-icon-danger { background: #ffeded; }
      .wwdash-alert-title { font-size: 14px; font-weight: 600; color: #111827; }
      .wwdash-alert-sub { font-size: 12px; color: #9ca3af; margin-top: 2px; }

      .wwdash-empty-note { font-size: 13px; color: #9ca3af; padding: 8px 0; }

      .wwdash-overview-grid {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 20px;
        margin-top: 20px;
      }

      .wwdash-insight-row,
      .wwdash-attention-row,
      .wwdash-recent-row {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 11px 0;
        border-bottom: 1px solid #f3f4f6;
        font-size: 13.5px;
        color: #374151;
      }

      .wwdash-insight-row:last-child,
      .wwdash-attention-row:last-child,
      .wwdash-recent-row:last-child {
        border-bottom: none;
      }

      .wwdash-insight-icon,
      .wwdash-recent-icon {
        width: 24px;
        flex-shrink: 0;
        text-align: center;
      }

      .wwdash-attention-panel {
        border-top: 3px solid #ff6b6b;
      }

      .wwdash-attention-row {
        color: #a83232;
      }

      .wwdash-recent-text {
        flex: 1;
        min-width: 0;
      }

      .wwdash-recent-date {
        color: #9ca3af;
        font-size: 12px;
        white-space: nowrap;
        margin-left: auto;
      }

      .wwdash-error {
        color: #cc3333;
        background: #ffeded;
        border: 1px solid #ffd2d2;
        border-radius: 12px;
        padding: 14px 16px;
        font-size: 13px;
      }

      @media (max-width: 900px) {
        .wwdash-overview-grid {
          grid-template-columns: 1fr;
        }
      }

      @media (max-width: 480px) {
        .wwdash-title { font-size: 22px; }
        .wwdash-stat-value { font-size: 26px; }
        .wwdash-stat-card, .wwdash-panel { padding: 18px; }
      }
    `}</style>
  );
}

function StatCard({ title, value, sub, icon, color }) {
  return (
    <div
      className="wwdash-stat-card"
      style={{ '--accent': color.base, '--accent-light': color.light }}
    >
      <div className="wwdash-stat-top">
        <span className="wwdash-stat-title">{title}</span>
        <span className="wwdash-stat-icon">{icon}</span>
      </div>
      <div className="wwdash-stat-value">{value}</div>
      <div className="wwdash-stat-sub">{sub}</div>
    </div>
  );
}


function QuickAction({ icon, label, color, onClick }) {
  return (
    <button
      type="button"
      className="wwdash-action"
      style={{
        '--accent': color.base,
        '--accent-light': color.light,
      }}
      onClick={onClick}
    >
      <span className="wwdash-action-icon">{icon}</span>
      <span>{label}</span>
    </button>
  );
}



function Dashboard({ setCurrentPage }) {
  const [stats, setStats] = useState(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');

useEffect(() => {
  const fetchDashboard = async () => {
    setLoading(true);
    setLoadError('');

    try {
      const adminGetAnalyticsDashboard = httpsCallable(
        functions,
        'adminGetAnalyticsDashboard'
      );

      const result = await adminGetAnalyticsDashboard();
      const receivedStats = result.data?.stats;

      if (!receivedStats) {
        throw new Error(
          'Dashboard data was missing from the server response.'
        );
      }

      const recentActivity = Array.isArray(
        receivedStats.recentActivity
      )
        ? receivedStats.recentActivity.map(event => {
            const date = toDate(event.createdAt);

            return {
              ...event,
              dateLabel: date ? formatDate(date) : '—',
            };
          })
        : [];

      setStats({
        ...receivedStats,
        recentActivity,
      });
    } catch (err) {
      console.error('Failed to load dashboard:', err);

      const detail = err?.code ? ` (${err.code})` : '';

      setLoadError(`Failed to load dashboard.${detail}`);
    } finally {
      setLoading(false);
    }
  };

  fetchDashboard();
}, []);

const percentage = (value, total) =>
  total > 0 ? Math.round((value / total) * 100) : 0;

const onboardedPct = stats
  ? percentage(stats.onboarded, stats.totalUsers)
  : 0;

const healthPct = stats
  ? percentage(stats.healthConnected, stats.totalUsers)
  : 0;

const premiumPct = stats
  ? percentage(stats.premiumUsers, stats.totalUsers)
  : 0;

const activeUsers = stats
  ? stats.totalUsers - stats.suspended
  : 0;

const activePct = stats
  ? percentage(activeUsers, stats.totalUsers)
  : 0;

const platformInsights =
  stats && stats.totalUsers > 0
    ? [
        `${onboardedPct}% of registered users have completed onboarding.`,
        `${healthPct}% of users have connected health data.`,
        `${activePct}% of users are currently active.`,
        `${premiumPct}% of users are currently premium.`,
      ]
    : [];

const attentionItems = [];

if (stats) {
  const notConnected =
    stats.totalUsers - stats.healthConnected;

  const notOnboarded =
    stats.totalUsers - stats.onboarded;

  if (notConnected > 0) {
    attentionItems.push(
      `⚠️ ${notConnected} user${
        notConnected === 1 ? '' : 's'
      } have not connected health data`
    );
  }

  if (stats.suspended > 0) {
    attentionItems.push(
      `🚫 ${stats.suspended} user${
        stats.suspended === 1 ? '' : 's'
      } currently suspended`
    );
  }

  if (stats.pendingBP > 0) {
    attentionItems.push(
      `⏳ ${stats.pendingBP} business partner application${
        stats.pendingBP === 1 ? '' : 's'
      } pending review`
    );
  }

  if (notOnboarded > 0) {
    attentionItems.push(
      `🧭 ${notOnboarded} user${
        notOnboarded === 1 ? '' : 's'
      } have not completed onboarding`
    );
  }

  if (
    stats.totalUsers > 0 &&
    stats.premiumUsers === 0
  ) {
    attentionItems.push(
      '⭐ No premium users currently registered'
    );
  }
}

  return (
    <div>
      <DashboardStyles />

      <div className="wwdash-header-row">
        <div>
          <h1 className="wwdash-title">Dashboard</h1>
          <p className="wwdash-subtitle">{new Date().toDateString()}</p>
        </div>
        <span className="wwdash-live-pill">
          <span className="wwdash-live-dot" />
          Live from Firebase
        </span>
      </div>

      {loading ? (
  <>
    <div className="wwdash-stats-grid">
      <div className="wwdash-skeleton-card" />
      <div className="wwdash-skeleton-card" />
      <div className="wwdash-skeleton-card" />
      <div className="wwdash-skeleton-card" />
    </div>

    <div className="wwdash-skeleton-panel" />
  </>
) : loadError ? (
  <div className="wwdash-panel">
    <div className="wwdash-error">
      {loadError}
    </div>
  </div>
) : !stats ? (
  <div className="wwdash-panel">
    <div className="wwdash-empty-note">
      Dashboard data is unavailable.
    </div>
  </div>
) : (
  <>
    <div className="wwdash-stats-grid">
      <StatCard
        title="Total Users"
        value={stats.totalUsers}
        sub="registered accounts"
        icon="👥"
        color={COLORS.primary}
      />

      <StatCard
        title="Total Plans"
        value={stats.totalPlans}
        sub="in plan library"
        icon="📋"
        color={COLORS.cyan}
      />

      <StatCard
        title="Total Exercises"
        value={stats.totalExercises}
        sub="in exercise library"
        icon="💪"
        color={COLORS.green}
      />

      <StatCard
        title="Pending BP Approvals"
        value={stats.pendingBP}
        sub="awaiting review"
        icon="🤝"
        color={COLORS.red}
      />
    </div>

    <div className="wwdash-panel">
      <div className="wwdash-panel-title">
        Quick Actions
      </div>

      <div className="wwdash-panel-subtitle">
        Jump straight into common admin tasks
      </div>

      

      <div className="wwdash-actions-grid">
        <QuickAction
          icon="🤝"
          label="Review BP Applications"
          color={COLORS.red}
          onClick={() => setCurrentPage('businessPartners')}
        />

        <QuickAction
          icon="👥"
          label="Manage Users"
          color={COLORS.primary}
          onClick={() => setCurrentPage('users')}
        />

        <QuickAction
          icon="💪"
          label="Add Exercise"
          color={COLORS.green}
          onClick={() => setCurrentPage('exercises')}
        />

        <QuickAction
          icon="⚙️"
          label="Configure XP Settings"
          color={COLORS.amber}
          onClick={() => setCurrentPage('settings')}
        />
      </div>
    </div>

    <div className="wwdash-overview-grid">
      <div className="wwdash-panel">
        <div className="wwdash-panel-title">
          Platform Insights
        </div>

        <div className="wwdash-panel-subtitle">
          Executive summary from current platform data
        </div>

        {platformInsights.length > 0 ? (
          platformInsights.map(text => (
            <div
              key={text}
              className="wwdash-insight-row"
            >
              <span className="wwdash-insight-icon">
                💡
              </span>
              <span>{text}</span>
            </div>
          ))
        ) : (
          <div className="wwdash-empty-note">
            Not enough user data to generate insights.
          </div>
        )}
      </div>

      <div className="wwdash-panel wwdash-attention-panel">
        <div className="wwdash-panel-title">
          Needs Attention
        </div>

        <div className="wwdash-panel-subtitle">
          Actionable items for the admin team
        </div>

        {attentionItems.length > 0 ? (
          attentionItems.map(text => (
            <div
              key={text}
              className="wwdash-attention-row"
            >
              <span>{text}</span>
            </div>
          ))
        ) : (
          <div className="wwdash-empty-note">
            Nothing needs attention right now.
          </div>
        )}
      </div>
    </div>

    <div
      className="wwdash-panel"
      style={{ marginTop: 20 }}
    >
      <div className="wwdash-panel-title">
        Recent Activity
      </div>

      <div className="wwdash-panel-subtitle">
        Latest timestamped events across the platform
      </div>

      {stats.recentActivity.length > 0 ? (
        stats.recentActivity.map((event, index) => (
          <div
            key={`${event.text}-${index}`}
            className="wwdash-recent-row"
          >
            <span className="wwdash-recent-icon">
              {event.icon}
            </span>

            <span className="wwdash-recent-text">
              {event.text}
            </span>

            <span className="wwdash-recent-date">
              {event.dateLabel}
            </span>
          </div>
        ))
      ) : (
        <div className="wwdash-empty-note">
          No recent timestamped activity yet.
        </div>
      )}
    </div>
  </>
  )}
</div>
);
}

export default Dashboard;
