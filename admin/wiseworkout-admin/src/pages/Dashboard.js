import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { collection, getDocs } from 'firebase/firestore';

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

function QuickAction({ icon, label, color }) {
  return (
    <button
      className="wwdash-action"
      style={{ '--accent': color.base, '--accent-light': color.light }}
    >
      <span className="wwdash-action-icon">{icon}</span>
      <span>{label}</span>
    </button>
  );
}

function AlertItem({ icon, tone, title, subtitle }) {
  return (
    <div className="wwdash-alert-item">
      <span className={`wwdash-alert-icon wwdash-alert-icon-${tone}`}>{icon}</span>
      <div>
        <div className="wwdash-alert-title">{title}</div>
        <div className="wwdash-alert-sub">{subtitle}</div>
      </div>
    </div>
  );
}

function Dashboard() {
  const [stats, setStats] = useState({
    totalUsers: 0,
    totalPlans: 0,
    totalExercises: 0,
    pendingBP: 0,
    suspendedUsers: 0,
  });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchStats = async () => {
      try {
        const [usersSnap, plansSnap, exercisesSnap, bpSnap] = await Promise.all([
          getDocs(collection(db, 'users')),
          getDocs(collection(db, 'plans')),
          getDocs(collection(db, 'exercises')),
          getDocs(collection(db, 'businessPartners')),
        ]);

        const pendingBP = bpSnap.docs.filter(doc => doc.data().status === 'pending').length;
        const suspendedUsers = usersSnap.docs.filter(doc => doc.data().accountStatus === 'suspended').length;

        setStats({
          totalUsers: usersSnap.size,
          totalPlans: plansSnap.size,
          totalExercises: exercisesSnap.size,
          pendingBP,
          suspendedUsers,
        });
      } catch (err) {
        console.error('Error fetching stats:', err);
      }
      setLoading(false);
    };

    fetchStats();
  }, []);

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
      ) : (
        <>
          <div className="wwdash-stats-grid">
            <StatCard title="Total Users" value={stats.totalUsers} sub="registered accounts" icon="👥" color={COLORS.primary} />
            <StatCard title="Total Plans" value={stats.totalPlans} sub="in plan library" icon="📋" color={COLORS.cyan} />
            <StatCard title="Total Exercises" value={stats.totalExercises} sub="in exercise library" icon="💪" color={COLORS.green} />
            <StatCard title="Pending BP Approvals" value={stats.pendingBP} sub="awaiting review" icon="🤝" color={COLORS.red} />
          </div>

          <div className="wwdash-panel">
            <div className="wwdash-panel-title">Quick Actions</div>
            <div className="wwdash-panel-subtitle">Jump straight into common admin tasks</div>
            <div className="wwdash-actions-grid">
              <QuickAction icon="🤝" label="Review BP Applications" color={COLORS.red} />
              <QuickAction icon="👥" label="Manage Users" color={COLORS.primary} />
              <QuickAction icon="💪" label="Add Exercise" color={COLORS.green} />
              <QuickAction icon="⚙️" label="Configure XP Settings" color={COLORS.amber} />
            </div>
          </div>

          <div className="wwdash-panel" style={{ marginTop: 20 }}>
            <div className="wwdash-panel-title">Recent Alerts</div>
            <div className="wwdash-panel-subtitle">Real, data-backed conditions that may need admin attention</div>
            {stats.pendingBP === 0 && stats.suspendedUsers === 0 ? (
              <div className="wwdash-empty-note">No alerts right now — everything looks good.</div>
            ) : (
              <>
                {stats.pendingBP > 0 && (
                  <AlertItem
                    icon="🤝"
                    tone="warning"
                    title={`${stats.pendingBP} pending business partner application${stats.pendingBP === 1 ? '' : 's'}`}
                    subtitle="Awaiting admin review"
                  />
                )}
                {stats.suspendedUsers > 0 && (
                  <AlertItem
                    icon="🚫"
                    tone="danger"
                    title={`${stats.suspendedUsers} suspended user${stats.suspendedUsers === 1 ? '' : 's'}`}
                    subtitle="Accounts currently suspended"
                  />
                )}
              </>
            )}
          </div>
        </>
      )}
    </div>
  );
}

export default Dashboard;
