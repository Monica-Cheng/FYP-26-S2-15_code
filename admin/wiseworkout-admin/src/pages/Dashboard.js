import React, { useEffect, useState } from 'react';
import { httpsCallable } from 'firebase/functions';
import {
  Activity,
  AlertTriangle,
  ArrowRight,
  CheckCircle2,
  ClipboardList,
  Dumbbell,
  FileText,
  HeartPulse,
  MessageSquare,
  Settings,
  ShieldCheck,
  Sparkles,
  Trophy,
  UserCog,
  User,
  Users,
} from 'lucide-react';
import { functions } from '../firebase';
import AdminStyles from '../styles/AdminStyles';
import MetricCard from '../components/ui/MetricCard';
import PageHeader from '../components/ui/PageHeader';
import SkeletonBlock from '../components/ui/SkeletonBlock';
import ErrorState from '../components/ui/ErrorState';
import EmptyState from '../components/ui/EmptyState';
import { toDate, formatDate } from '../utils/dateUtils';

function DashboardStyles() {
  return (
    <style>{`
      .wwdash-page {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-6);
      }
      .wwdash-live-pill {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        min-height: 32px;
        padding: 6px 12px;
        border-radius: 999px;
        border: 1px solid color-mix(in srgb, var(--ww-success) 14%, transparent);
        background: var(--ww-card);
        color: var(--ww-text-sec);
        font-size: var(--ww-type-secondary-size);
        font-weight: 600;
      }
      .wwdash-live-dot {
        width: 8px;
        height: 8px;
        border-radius: 50%;
        background: var(--ww-success);
      }
      .wwdash-primary-grid {
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        gap: var(--ww-space-4);
      }
      .wwdash-primary-grid .wwa-metric-card {
        min-height: 0;
        padding: 18px;
        box-shadow: none;
      }
      .wwdash-primary-grid .wwa-metric-card__value {
        font-size: 28px;
      }
      .wwdash-loading-grid {
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        gap: var(--ww-space-4);
      }
      .wwdash-loading-grid .wwa-skeleton {
        border-radius: var(--ww-radius-card);
      }
      .wwdash-main-grid {
        display: grid;
        grid-template-columns: minmax(0, 1.8fr) minmax(320px, 1fr);
        gap: var(--ww-space-5);
        align-items: start;
      }
      .wwdash-side-stack {
        display: grid;
        gap: var(--ww-space-5);
      }
      .wwdash-section-header {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 12px;
        margin-bottom: 16px;
      }
      .wwdash-section-title {
        font-size: var(--ww-type-section-title-size);
        font-weight: var(--ww-type-section-title-weight);
        color: var(--ww-primary-dark);
        line-height: 1.2;
      }
      .wwdash-section-subtitle {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
        margin-top: 4px;
      }
      .wwdash-quick-actions {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 12px;
      }
      .wwdash-quick-action {
        width: 100%;
        min-height: 48px;
        padding: 12px 14px;
        border-radius: 12px;
        border: 1px solid var(--ww-divider);
        background: var(--ww-card);
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        text-align: left;
        transition: border-color 0.12s ease, background 0.12s ease, box-shadow 0.12s ease;
      }
      .wwdash-quick-action:hover {
        border-color: var(--ww-primary);
        background: var(--ww-hover);
      }
      .wwdash-quick-action__content {
        display: flex;
        align-items: center;
        gap: 12px;
        min-width: 0;
      }
      .wwdash-quick-action__icon {
        width: 32px;
        height: 32px;
        border-radius: 10px;
        background: var(--ww-elevated);
        color: var(--ww-primary-dark);
        display: inline-flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
      }
      .wwdash-quick-action__label {
        font-size: var(--ww-type-body-size);
        font-weight: 600;
        color: var(--ww-text);
      }
      .wwdash-quick-action__arrow {
        color: var(--ww-text-sec);
        flex-shrink: 0;
      }
      .wwdash-health-list,
      .wwdash-attention-list,
      .wwdash-recent-list {
        display: flex;
        flex-direction: column;
      }
      .wwdash-health-row,
      .wwdash-attention-row,
      .wwdash-recent-row {
        display: flex;
        align-items: flex-start;
        gap: 12px;
        padding: 14px 0;
        border-bottom: 1px solid var(--ww-divider);
      }
      .wwdash-health-row:first-child,
      .wwdash-attention-row:first-child,
      .wwdash-recent-row:first-child {
        padding-top: 0;
      }
      .wwdash-health-row:last-child,
      .wwdash-attention-row:last-child,
      .wwdash-recent-row:last-child {
        padding-bottom: 0;
        border-bottom: none;
      }
      .wwdash-health-row__icon,
      .wwdash-attention-row__icon,
      .wwdash-recent-row__icon {
        width: 32px;
        height: 32px;
        border-radius: 10px;
        background: var(--ww-elevated);
        color: var(--ww-primary-dark);
        display: inline-flex;
        align-items: center;
        justify-content: center;
        flex-shrink: 0;
      }
      .wwdash-attention-row__icon-warning {
        background: var(--ww-warning-bg);
        color: #92400E;
      }
      .wwdash-attention-row__icon-danger {
        background: var(--ww-danger-bg);
        color: #b91c1c;
      }
      .wwdash-attention-row__icon-success {
        background: var(--ww-success-bg);
        color: #166534;
      }
      .wwdash-health-row__main,
      .wwdash-attention-row__main,
      .wwdash-recent-row__main {
        flex: 1;
        min-width: 0;
      }
      .wwdash-health-row__top {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 12px;
        margin-bottom: 6px;
      }
      .wwdash-health-row__label,
      .wwdash-attention-row__title,
      .wwdash-recent-row__title {
        font-size: var(--ww-type-body-size);
        font-weight: 600;
        color: var(--ww-text);
      }
      .wwdash-health-row__value {
        font-size: 18px;
        font-weight: 800;
        color: var(--ww-primary-dark);
        white-space: nowrap;
      }
      .wwdash-health-row__meta,
      .wwdash-attention-row__detail,
      .wwdash-recent-row__detail {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
      }
      .wwdash-health-progress {
        width: 100%;
        height: 8px;
        border-radius: 999px;
        background: var(--ww-elevated);
        overflow: hidden;
        margin-top: 10px;
      }
      .wwdash-health-progress__fill {
        height: 100%;
        border-radius: inherit;
        background: var(--ww-primary);
      }
      .wwdash-recent-row {
        align-items: center;
      }
      .wwdash-recent-row__date {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
        white-space: nowrap;
        margin-left: auto;
      }
      .wwdash-empty-compact {
        padding: 12px 0 0;
      }
      @media (max-width: 1200px) {
        .wwdash-primary-grid,
        .wwdash-loading-grid {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
      }
      @media (max-width: 960px) {
        .wwdash-main-grid {
          grid-template-columns: minmax(0, 1fr);
        }
      }
      @media (max-width: 640px) {
        .wwdash-primary-grid,
        .wwdash-loading-grid,
        .wwdash-quick-actions {
          grid-template-columns: minmax(0, 1fr);
        }
        .wwdash-health-row__top {
          flex-direction: column;
          align-items: flex-start;
          gap: 4px;
        }
        .wwdash-recent-row {
          align-items: flex-start;
          flex-wrap: wrap;
        }
        .wwdash-recent-row__date {
          margin-left: 44px;
        }
      }
    `}</style>
  );
}

function getActivityIcon(text = '') {
  const lower = text.toLowerCase();

  if (lower.includes('post') || lower.includes('comment') || lower.includes('reaction')) return FileText;
  if (lower.includes('message')) return MessageSquare;
  if (lower.includes('challenge')) return Trophy;
  if (lower.includes('plan')) return ClipboardList;
  if (lower.includes('user')) return User;
  if (lower.includes('exercise')) return Dumbbell;
  if (lower.includes('partner') || lower.includes('application')) return UserCog;
  return Activity;
}

function QuickAction({ icon: Icon, label, onClick }) {
  return (
    <button type="button" className="wwdash-quick-action" onClick={onClick}>
      <span className="wwdash-quick-action__content">
        <span className="wwdash-quick-action__icon">
          <Icon aria-hidden="true" size={16} strokeWidth={2} />
        </span>
        <span className="wwdash-quick-action__label">{label}</span>
      </span>
      <span className="wwdash-quick-action__arrow" aria-hidden="true">
        <ArrowRight size={16} strokeWidth={2} />
      </span>
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
        const adminGetAnalyticsDashboard = httpsCallable(functions, 'adminGetAnalyticsDashboard');
        const result = await adminGetAnalyticsDashboard();
        const receivedStats = result.data?.stats;

        if (!receivedStats) {
          throw new Error('Dashboard data was missing from the server response.');
        }

        const recentActivity = Array.isArray(receivedStats.recentActivity)
          ? receivedStats.recentActivity.map((event) => {
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

  const percentage = (value, total) => (total > 0 ? Math.round((value / total) * 100) : 0);

  const onboardedPct = stats ? percentage(stats.onboarded, stats.totalUsers) : 0;
  const healthPct = stats ? percentage(stats.healthConnected, stats.totalUsers) : 0;
  const premiumPct = stats ? percentage(stats.premiumUsers, stats.totalUsers) : 0;
  const activeUsers = stats ? stats.totalUsers - stats.suspended : 0;
  const activePct = stats ? percentage(activeUsers, stats.totalUsers) : 0;

  const primaryMetrics = stats
    ? [
        {
          label: 'Total Users',
          value: stats.totalUsers,
          meta: 'Registered accounts',
        },
        {
          label: 'Total Plans',
          value: stats.totalPlans,
          meta: 'In plan library',
        },
        {
          label: 'Total Exercises',
          value: stats.totalExercises,
          meta: 'In exercise library',
        },
        {
          label: 'Pending BP Approvals',
          value: stats.pendingBP,
          meta: 'Awaiting review',
          statusLabel: stats.pendingBP > 0 ? 'Needs review' : 'Up to date',
          statusTone: stats.pendingBP > 0 ? 'warning' : 'neutral',
        },
      ]
    : [];

  const platformHealth = stats
    ? [
        {
          label: 'Onboarding completion',
          value: `${onboardedPct}%`,
          detail: `${stats.onboarded} of ${stats.totalUsers} users completed onboarding`,
          progress: onboardedPct,
          icon: ShieldCheck,
        },
        {
          label: 'Health connections',
          value: `${healthPct}%`,
          detail: `${stats.healthConnected} users connected health data`,
          progress: healthPct,
          icon: HeartPulse,
        },
        {
          label: 'Active accounts',
          value: `${activePct}%`,
          detail: `${activeUsers} active, ${stats.suspended} suspended`,
          progress: activePct,
          icon: Activity,
        },
        {
          label: 'Premium adoption',
          value: `${premiumPct}%`,
          detail: `${stats.premiumUsers} premium users currently registered`,
          progress: premiumPct,
          icon: Sparkles,
        },
      ]
    : [];

  const attentionItems = [];

  if (stats) {
    const notConnected = stats.totalUsers - stats.healthConnected;
    const notOnboarded = stats.totalUsers - stats.onboarded;

    if (stats.pendingBP > 0) {
      attentionItems.push({
        key: 'pending-bp',
        title: `${stats.pendingBP} business partner application${stats.pendingBP === 1 ? '' : 's'} pending review`,
        detail: 'Review applications from the Business Partners page.',
        tone: 'warning',
      });
    }

    if (stats.suspended > 0) {
      attentionItems.push({
        key: 'suspended-users',
        title: `${stats.suspended} suspended user${stats.suspended === 1 ? '' : 's'}`,
        detail: 'Suspended accounts are excluded from active-user operations.',
        tone: 'danger',
      });
    }

    if (notConnected > 0) {
      attentionItems.push({
        key: 'health-connections',
        title: `${notConnected} user${notConnected === 1 ? '' : 's'} without health data`,
        detail: 'Health integrations remain incomplete for part of the user base.',
        tone: 'warning',
      });
    }

    if (notOnboarded > 0) {
      attentionItems.push({
        key: 'onboarding',
        title: `${notOnboarded} user${notOnboarded === 1 ? '' : 's'} have not completed onboarding`,
        detail: 'These accounts may have reduced engagement or incomplete profiles.',
        tone: 'warning',
      });
    }

    if (stats.totalUsers > 0 && stats.premiumUsers === 0) {
      attentionItems.push({
        key: 'premium-users',
        title: 'No premium users currently registered',
        detail: 'Premium conversion is currently at 0%.',
        tone: 'danger',
      });
    }
  }

  return (
    <div className="wwdash-page">
      <AdminStyles />
      <DashboardStyles />

      <PageHeader
        title="Dashboard"
        description={new Date().toDateString()}
        actions={
          <span className="wwdash-live-pill">
            <span className="wwdash-live-dot" />
            Live from Firebase
          </span>
        }
      />

      {loading ? (
        <>
          <div className="wwdash-loading-grid">
            {Array.from({ length: 4 }).map((_, index) => (
              <SkeletonBlock key={index} height={118} />
            ))}
          </div>
          <div className="wwdash-main-grid">
            <SkeletonBlock height={360} />
            <SkeletonBlock height={360} />
          </div>
        </>
      ) : loadError ? (
        <ErrorState title="Failed to load dashboard" message={loadError} />
      ) : !stats ? (
        <div className="wwa-panel">
          <EmptyState icon={null} title="No dashboard data available" message="The dashboard response did not include usable data." />
        </div>
      ) : (
        <>
          <div className="wwdash-primary-grid">
            {primaryMetrics.map((metric) => (
              <MetricCard
                key={metric.label}
                label={metric.label}
                value={metric.value}
                meta={metric.meta}
                statusLabel={metric.statusLabel}
                statusTone={metric.statusTone}
              />
            ))}
          </div>

          <div className="wwdash-main-grid">
            <section className="wwa-panel">
              <div className="wwdash-section-header">
                <div>
                  <h2 className="wwdash-section-title">Recent Activity</h2>
                  <p className="wwdash-section-subtitle">Latest timestamped events across the platform</p>
                </div>
              </div>

              {stats.recentActivity.length > 0 ? (
                <div className="wwdash-recent-list">
                  {stats.recentActivity.map((event, index) => {
                    const Icon = getActivityIcon(event.text);

                    return (
                      <div key={`${event.text}-${index}`} className="wwdash-recent-row">
                        <span className="wwdash-recent-row__icon">
                          <Icon aria-hidden="true" size={16} strokeWidth={2} />
                        </span>
                        <div className="wwdash-recent-row__main">
                          <div className="wwdash-recent-row__title">{event.text}</div>
                          {event.type ? <div className="wwdash-recent-row__detail">{event.type}</div> : null}
                        </div>
                        <div className="wwdash-recent-row__date">{event.dateLabel}</div>
                      </div>
                    );
                  })}
                </div>
              ) : (
                <EmptyState
                  className="wwdash-empty-compact"
                  icon={null}
                  title="No recent activity yet"
                  message="Timestamped platform events will appear here once available."
                />
              )}
            </section>

            <div className="wwdash-side-stack">
              <section className="wwa-panel">
                <div className="wwdash-section-header">
                  <div>
                    <h2 className="wwdash-section-title">Needs Attention</h2>
                    <p className="wwdash-section-subtitle">Operational items requiring admin follow-up</p>
                  </div>
                </div>

                {attentionItems.length > 0 ? (
                  <div className="wwdash-attention-list">
                    {attentionItems.map((item) => (
                      <div key={item.key} className="wwdash-attention-row">
                        <span
                          className={`wwdash-attention-row__icon wwdash-attention-row__icon-${item.tone}`}
                        >
                          <AlertTriangle aria-hidden="true" size={16} strokeWidth={2} />
                        </span>
                        <div className="wwdash-attention-row__main">
                          <div className="wwdash-attention-row__title">{item.title}</div>
                          <div className="wwdash-attention-row__detail">{item.detail}</div>
                        </div>
                      </div>
                    ))}
                  </div>
                ) : (
                  <div className="wwdash-attention-row">
                    <span className="wwdash-attention-row__icon wwdash-attention-row__icon-success">
                      <CheckCircle2 aria-hidden="true" size={16} strokeWidth={2} />
                    </span>
                    <div className="wwdash-attention-row__main">
                      <div className="wwdash-attention-row__title">Nothing needs attention right now</div>
                      <div className="wwdash-attention-row__detail">Current operational checks are clear.</div>
                    </div>
                  </div>
                )}
              </section>

              <section className="wwa-panel">
                <div className="wwdash-section-header">
                  <div>
                    <h2 className="wwdash-section-title">Platform Health</h2>
                    <p className="wwdash-section-subtitle">High-level operational summary from current platform data</p>
                  </div>
                </div>

                {platformHealth.length > 0 ? (
                  <div className="wwdash-health-list">
                    {platformHealth.map((item) => {
                      const Icon = item.icon;

                      return (
                        <div key={item.label} className="wwdash-health-row">
                          <span className="wwdash-health-row__icon">
                            <Icon aria-hidden="true" size={16} strokeWidth={2} />
                          </span>
                          <div className="wwdash-health-row__main">
                            <div className="wwdash-health-row__top">
                              <div className="wwdash-health-row__label">{item.label}</div>
                              <div className="wwdash-health-row__value">{item.value}</div>
                            </div>
                            <div className="wwdash-health-row__meta">{item.detail}</div>
                            <div className="wwdash-health-progress" aria-hidden="true">
                              <div className="wwdash-health-progress__fill" style={{ width: `${item.progress}%` }} />
                            </div>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                ) : (
                  <EmptyState
                    className="wwdash-empty-compact"
                    icon={null}
                    title="Not enough data yet"
                    message="Platform health metrics will appear once user data is available."
                  />
                )}
              </section>
            </div>
          </div>

          <section className="wwa-panel">
            <div className="wwdash-section-header">
              <div>
                <h2 className="wwdash-section-title">Quick Actions</h2>
                <p className="wwdash-section-subtitle">Common admin destinations for operational work</p>
              </div>
            </div>

            <div className="wwdash-quick-actions">
              <QuickAction icon={UserCog} label="Review BP Applications" onClick={() => setCurrentPage('businessPartners')} />
              <QuickAction icon={Users} label="Manage Users" onClick={() => setCurrentPage('users')} />
              <QuickAction icon={Dumbbell} label="Add Exercise" onClick={() => setCurrentPage('exercises')} />
              <QuickAction icon={Settings} label="Configure XP Settings" onClick={() => setCurrentPage('settings')} />
            </div>
          </section>
        </>
      )}
    </div>
  );
}

export default Dashboard;
