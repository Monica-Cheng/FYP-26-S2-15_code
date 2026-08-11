import React, { useEffect, useState } from 'react';
import { httpsCallable } from 'firebase/functions';
import * as XLSX from 'xlsx';
import {
  Activity,
  Crown,
  Download,
  Dumbbell,
  HeartPulse,
  LayoutGrid,
  Users,
} from 'lucide-react';
import { functions } from '../firebase';
import AdminStyles from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import SkeletonBlock from '../components/ui/SkeletonBlock';
import EmptyState from '../components/ui/EmptyState';
import ErrorState from '../components/ui/ErrorState';
import MetricCard from '../components/ui/MetricCard';
import DonutChart from '../components/ui/DonutChart';
import BarChart from '../components/ui/BarChart';
import { toDate, formatDate } from '../utils/dateUtils';

const STATUS_GREEN = '#22C55E';
const STATUS_RED = '#EF4444';
const BRAND_PURPLE = '#6C7EE8';
const NEUTRAL_GRAY = '#C8C8D8';

const pct = (num, den) => (den > 0 ? Math.round((num / den) * 100) : 0);

function AnalyticsStyles() {
  return (
    <style>{`
      .wwanalytics-page {
        display: flex;
        flex-direction: column;
        gap: var(--ww-space-6);
      }
      .wwanalytics-primary-grid {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: var(--ww-space-4);
      }
      .wwanalytics-loading-grid {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: var(--ww-space-4);
      }
      .wwanalytics-loading-grid .wwa-skeleton {
        border-radius: var(--ww-radius-card);
      }
      .wwanalytics-section {
        display: flex;
        flex-direction: column;
        gap: 18px;
      }
      .wwanalytics-section-header {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 12px;
      }
      .wwanalytics-section-title {
        font-size: var(--ww-type-section-title-size);
        font-weight: var(--ww-type-section-title-weight);
        color: var(--ww-primary-dark);
        line-height: 1.2;
      }
      .wwanalytics-section-subtitle {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
        margin-top: 4px;
      }
      .wwanalytics-summary-grid {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 12px 20px;
      }
      .wwanalytics-summary-item {
        padding: 12px 0;
        border-bottom: 1px solid var(--ww-divider);
      }
      .wwanalytics-summary-item:nth-last-child(-n + 2) {
        border-bottom: none;
      }
      .wwanalytics-summary-label {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
        margin-bottom: 6px;
      }
      .wwanalytics-summary-value {
        font-size: 22px;
        font-weight: 800;
        color: var(--ww-primary-dark);
        line-height: 1.1;
      }
      .wwanalytics-summary-meta {
        font-size: var(--ww-type-secondary-size);
        font-weight: var(--ww-type-secondary-weight);
        color: var(--ww-text-sec);
        margin-top: 4px;
      }
      .wwanalytics-ops-grid {
        display: grid;
        grid-template-columns: minmax(0, 1.35fr) minmax(280px, 1fr);
        gap: var(--ww-space-5);
      }
      .wwanalytics-ops-list {
        display: flex;
        flex-direction: column;
      }
      .wwanalytics-ops-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        padding: 14px 0;
        border-bottom: 1px solid var(--ww-divider);
      }
      .wwanalytics-ops-row:first-child {
        padding-top: 0;
      }
      .wwanalytics-ops-row:last-child {
        padding-bottom: 0;
        border-bottom: none;
      }
      .wwanalytics-ops-label {
        font-size: var(--ww-type-body-size);
        font-weight: 600;
        color: var(--ww-text);
      }
      .wwanalytics-ops-value {
        font-size: 16px;
        font-weight: 700;
        color: var(--ww-primary-dark);
        white-space: nowrap;
      }
      @media (max-width: 1200px) {
        .wwanalytics-primary-grid,
        .wwanalytics-loading-grid {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
      }
      @media (max-width: 900px) {
        .wwanalytics-ops-grid,
        .wwanalytics-summary-grid {
          grid-template-columns: minmax(0, 1fr);
        }
      }
      @media (max-width: 640px) {
        .wwanalytics-primary-grid,
        .wwanalytics-loading-grid {
          grid-template-columns: minmax(0, 1fr);
        }
      }
    `}</style>
  );
}

function Analytics() {
  const [stats, setStats] = useState(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');

  useEffect(() => {
    const fetchAnalytics = async () => {
      setLoading(true);
      setLoadError('');

      try {
        const adminGetAnalyticsDashboard = httpsCallable(functions, 'adminGetAnalyticsDashboard');
        const result = await adminGetAnalyticsDashboard();
        const receivedStats = result.data?.stats;

        if (!receivedStats) {
          throw new Error('Analytics data was missing from the server response.');
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
          levelDistribution: Array.isArray(receivedStats.levelDistribution) ? receivedStats.levelDistribution : [],
          difficultyCounts:
            receivedStats.difficultyCounts && typeof receivedStats.difficultyCounts === 'object'
              ? receivedStats.difficultyCounts
              : {},
          challengeTypeCounts:
            receivedStats.challengeTypeCounts && typeof receivedStats.challengeTypeCounts === 'object'
              ? receivedStats.challengeTypeCounts
              : {},
          recentActivity,
        });
      } catch (err) {
        console.error('Failed to load analytics:', err);
        const detail = err?.code ? ` (${err.code})` : '';
        setLoadError(`Failed to load analytics.${detail}`);
      } finally {
        setLoading(false);
      }
    };

    fetchAnalytics();
  }, []);

  const onboardedPct = stats ? pct(stats.onboarded, stats.totalUsers) : 0;
  const healthPct = stats ? pct(stats.healthConnected, stats.totalUsers) : 0;
  const premiumPct = stats ? pct(stats.premiumUsers, stats.totalUsers) : 0;
  const suspendedPct = stats ? pct(stats.suspended, stats.totalUsers) : 0;
  const activePct = stats ? 100 - suspendedPct : 0;
  const activeUsers = stats ? stats.totalUsers - stats.suspended : 0;

  const cards = stats
    ? [
        { label: 'Total Users', value: stats.totalUsers, meta: 'Registered accounts', icon: <Users size={16} strokeWidth={2} /> },
        {
          label: 'Active Users',
          value: activeUsers,
          meta: `${activePct}% of total users`,
          icon: <Activity size={16} strokeWidth={2} />,
        },
        {
          label: 'Health Connected',
          value: stats.healthConnected,
          meta: `${healthPct}% connected`,
          icon: <HeartPulse size={16} strokeWidth={2} />,
        },
        {
          label: 'Premium Users',
          value: stats.premiumUsers,
          meta: `${premiumPct}% premium adoption`,
          icon: <Crown size={16} strokeWidth={2} />,
        },
        { label: 'Total Plans', value: stats.totalPlans, meta: 'Plan library size', icon: <LayoutGrid size={16} strokeWidth={2} /> },
        {
          label: 'Total Exercises',
          value: stats.totalExercises,
          meta: 'Exercise library size',
          icon: <Dumbbell size={16} strokeWidth={2} />,
        },
      ]
    : [];

  const contentMetrics = stats
    ? [
        {
          label: 'Total Posts',
          value: stats.totalPosts,
          meta: 'All post types',
        },
        {
          label: 'Meal Posts',
          value: stats.totalMealPosts,
          meta: 'Nutrition-related posts',
        },
        {
          label: 'Reactions',
          value: stats.totalReactions,
          meta: 'Across all posts',
        },
        {
          label: 'Comments',
          value: stats.totalComments,
          meta: 'Across all posts',
        },
        {
          label: 'Avg Calories / Meal Post',
          value: stats.avgCalories !== null ? stats.avgCalories : '—',
          meta: 'Average from meal posts',
        },
        {
          label: 'Avg Protein / Carbs / Fat',
          value:
            [stats.avgProtein, stats.avgCarbs, stats.avgFat].every((value) => value === null)
              ? '—'
              : `${stats.avgProtein ?? '—'}g / ${stats.avgCarbs ?? '—'}g / ${stats.avgFat ?? '—'}g`,
          meta: 'Meal macro averages',
        },
      ]
    : [];

  const handleExport = () => {
    if (!stats) return;

    const workbook = XLSX.utils.book_new();

    const summaryRows = [
      { Metric: 'Total Users', Value: stats.totalUsers, Percentage: '' },
      { Metric: 'Onboarded Users', Value: stats.onboarded, Percentage: `${onboardedPct}%` },
      { Metric: 'Health Connected', Value: stats.healthConnected, Percentage: `${healthPct}%` },
      { Metric: 'Premium Users', Value: stats.premiumUsers, Percentage: `${premiumPct}%` },
      { Metric: 'Suspended Users', Value: stats.suspended, Percentage: `${suspendedPct}%` },
      { Metric: 'Total Plans', Value: stats.totalPlans, Percentage: '' },
      { Metric: 'Total Exercises', Value: stats.totalExercises, Percentage: '' },
      { Metric: 'Total Challenges', Value: stats.totalChallenges, Percentage: '' },
      { Metric: 'Total Business Partners', Value: stats.totalBP, Percentage: '' },
      { Metric: 'Approved BPs', Value: stats.approvedBP, Percentage: '' },
      { Metric: 'Pending BP Applications', Value: stats.pendingBP, Percentage: '' },
    ];
    const summarySheet = XLSX.utils.json_to_sheet(summaryRows);
    summarySheet['!cols'] = [{ wch: 28 }, { wch: 12 }, { wch: 12 }];
    XLSX.utils.book_append_sheet(workbook, summarySheet, 'Summary');

    const freeUsers = stats.totalUsers - stats.premiumUsers;
    const notConnected = stats.totalUsers - stats.healthConnected;
    const notOnboarded = stats.totalUsers - stats.onboarded;
    const userRows = [
      { Metric: 'Premium Users', Value: stats.premiumUsers, Percentage: `${premiumPct}%` },
      { Metric: 'Free Users', Value: freeUsers, Percentage: `${100 - premiumPct}%` },
      { Metric: 'Active Users', Value: activeUsers, Percentage: `${activePct}%` },
      { Metric: 'Suspended Users', Value: stats.suspended, Percentage: `${suspendedPct}%` },
      { Metric: 'Health Connected', Value: stats.healthConnected, Percentage: `${healthPct}%` },
      { Metric: 'Not Connected', Value: notConnected, Percentage: `${100 - healthPct}%` },
      { Metric: 'Onboarded', Value: stats.onboarded, Percentage: `${onboardedPct}%` },
      { Metric: 'Not Onboarded', Value: notOnboarded, Percentage: `${100 - onboardedPct}%` },
      {},
      { Metric: 'Level', Value: 'User Count' },
      ...stats.levelDistribution.map((level) => ({ Metric: level.label, Value: level.value })),
    ];
    const userSheet = XLSX.utils.json_to_sheet(userRows, { skipHeader: true });
    userSheet['!cols'] = [{ wch: 22 }, { wch: 14 }, { wch: 12 }];
    XLSX.utils.book_append_sheet(workbook, userSheet, 'User Analytics');

    if (stats.totalPosts > 0) {
      const contentRows = [
        { Metric: 'Total Posts', Value: stats.totalPosts },
        { Metric: 'Total Meal Posts', Value: stats.totalMealPosts },
        { Metric: 'Total Reactions', Value: stats.totalReactions },
        { Metric: 'Total Comments', Value: stats.totalComments },
        { Metric: 'Avg Calories / Meal Post', Value: stats.avgCalories ?? 'N/A' },
        { Metric: 'Avg Protein (g)', Value: stats.avgProtein ?? 'N/A' },
        { Metric: 'Avg Carbs (g)', Value: stats.avgCarbs ?? 'N/A' },
        { Metric: 'Avg Fat (g)', Value: stats.avgFat ?? 'N/A' },
      ];
      const contentSheet = XLSX.utils.json_to_sheet(contentRows);
      contentSheet['!cols'] = [{ wch: 26 }, { wch: 14 }];
      XLSX.utils.book_append_sheet(workbook, contentSheet, 'Content Analytics');
    }

    if (stats.totalExercises > 0) {
      const exerciseRows = [
        { Metric: 'Total Exercises', Value: stats.totalExercises },
        {},
        { Metric: 'Difficulty', Value: 'Count' },
        ...Object.entries(stats.difficultyCounts)
          .filter(([, count]) => count > 0)
          .map(([difficulty, count]) => ({ Metric: difficulty, Value: count })),
      ];
      const exerciseSheet = XLSX.utils.json_to_sheet(exerciseRows, { skipHeader: true });
      exerciseSheet['!cols'] = [{ wch: 22 }, { wch: 14 }];
      XLSX.utils.book_append_sheet(workbook, exerciseSheet, 'Exercise Analytics');
    }

    if (stats.totalChallenges > 0) {
      const challengeRows = [
        { Metric: 'Total Challenges', Value: stats.totalChallenges },
        {},
        { Metric: 'Type', Value: 'Count' },
        ...Object.entries(stats.challengeTypeCounts).map(([type, count]) => ({ Metric: type, Value: count })),
      ];
      const challengeSheet = XLSX.utils.json_to_sheet(challengeRows, { skipHeader: true });
      challengeSheet['!cols'] = [{ wch: 22 }, { wch: 14 }];
      XLSX.utils.book_append_sheet(workbook, challengeSheet, 'Challenge Analytics');
    }

    const attentionItems = [];
    if (stats) {
      const notConnected = stats.totalUsers - stats.healthConnected;
      const notOnboarded = stats.totalUsers - stats.onboarded;
      if (notConnected > 0) attentionItems.push(`${notConnected} users have not connected health data`);
      if (stats.suspended > 0) attentionItems.push(`${stats.suspended} users currently suspended`);
      if (stats.pendingBP > 0) attentionItems.push(`${stats.pendingBP} business partner applications pending review`);
      if (notOnboarded > 0) attentionItems.push(`${notOnboarded} users have not completed onboarding`);
      if (stats.totalUsers > 0 && stats.premiumUsers === 0) attentionItems.push('No premium users currently registered');
    }

    if (attentionItems.length > 0) {
      const attentionSheet = XLSX.utils.json_to_sheet(attentionItems.map((item) => ({ Item: item })));
      attentionSheet['!cols'] = [{ wch: 50 }];
      XLSX.utils.book_append_sheet(workbook, attentionSheet, 'Needs Attention');
    }

    XLSX.writeFile(workbook, 'WiseWorkout_Analytics.xlsx');
  };

  const contentEmpty = !stats || stats.totalPosts <= 0;

  return (
    <div className="wwanalytics-page">
      <AdminStyles />
      <AnalyticsStyles />

      <PageHeader
        title="Analytics"
        description={loading ? 'Loading analytics…' : 'Platform overview live from Firebase'}
        actions={
          !loading && stats ? (
            <button className="wwa-btn wwa-btn-secondary" onClick={handleExport}>
              <Download aria-hidden="true" size={16} strokeWidth={2} />
              Export to Excel
            </button>
          ) : null
        }
      />

      {loading ? (
        <>
          <div className="wwanalytics-loading-grid">
            {Array.from({ length: 6 }).map((_, index) => (
              <SkeletonBlock key={index} height={116} />
            ))}
          </div>
          <SkeletonBlock height={340} />
          <SkeletonBlock height={260} />
        </>
      ) : loadError ? (
        <ErrorState title="Failed to load analytics" message={loadError} />
      ) : !stats ? (
        <div className="wwa-panel">
          <EmptyState icon={null} title="No analytics available" message="The analytics response did not include usable data." />
        </div>
      ) : (
        <>
          <div className="wwanalytics-primary-grid">
            {cards.map((card) => (
              <MetricCard key={card.label} label={card.label} value={card.value} meta={card.meta} icon={card.icon} />
            ))}
          </div>

          <section className="wwa-panel wwanalytics-section">
            <div className="wwanalytics-section-header">
              <div>
                <h2 className="wwanalytics-section-title">User & Platform Analytics</h2>
                <p className="wwanalytics-section-subtitle">Core account health, engagement, and platform distribution metrics</p>
              </div>
            </div>

            <div className="wwa-charts-grid" style={{ marginTop: 0 }}>
              <DonutChart
                title="Premium vs Free Users"
                data={[
                  { label: 'Premium', value: stats.premiumUsers, color: BRAND_PURPLE },
                  { label: 'Free', value: stats.totalUsers - stats.premiumUsers, color: NEUTRAL_GRAY },
                ]}
              />

              <DonutChart
                title="Active vs Suspended Users"
                data={[
                  { label: 'Active', value: activeUsers, color: STATUS_GREEN },
                  { label: 'Suspended', value: stats.suspended, color: STATUS_RED },
                ]}
              />

              <DonutChart
                title="Health Connected"
                data={[
                  { label: 'Connected', value: stats.healthConnected, color: BRAND_PURPLE },
                  { label: 'Not Connected', value: stats.totalUsers - stats.healthConnected, color: NEUTRAL_GRAY },
                ]}
              />

              {stats.levelDistribution.length > 0 ? (
                <BarChart title="User Level Distribution" data={stats.levelDistribution} color={BRAND_PURPLE} />
              ) : (
                <div className="wwa-chart-card">
                  <div className="wwa-chart-title">User Level Distribution</div>
                  <EmptyState icon={null} title="No level data yet" message="Level distribution will appear once user level data is available." />
                </div>
              )}
            </div>
          </section>

          <div className="wwanalytics-ops-grid">
            <section className="wwa-panel wwanalytics-section">
              <div className="wwanalytics-section-header">
                <div>
                  <h2 className="wwanalytics-section-title">Content Analytics</h2>
                  <p className="wwanalytics-section-subtitle">Content volume, social engagement, and nutrition summary metrics</p>
                </div>
              </div>

              {contentEmpty ? (
                <EmptyState
                  icon={null}
                  title="No content analytics yet"
                  message="Content metrics will appear once posts data is available."
                />
              ) : (
                <div className="wwanalytics-summary-grid">
                  {contentMetrics.map((metric) => (
                    <div key={metric.label} className="wwanalytics-summary-item">
                      <div className="wwanalytics-summary-label">{metric.label}</div>
                      <div className="wwanalytics-summary-value">{metric.value}</div>
                      <div className="wwanalytics-summary-meta">{metric.meta}</div>
                    </div>
                  ))}
                </div>
              )}
            </section>

            <section className="wwa-panel wwanalytics-section">
              <div className="wwanalytics-section-header">
                <div>
                  <h2 className="wwanalytics-section-title">Operational Summary</h2>
                  <p className="wwanalytics-section-subtitle">Supporting counts for business partners, challenges, and onboarding</p>
                </div>
              </div>

              <div className="wwanalytics-ops-list">
                <div className="wwanalytics-ops-row">
                  <div className="wwanalytics-ops-label">Onboarded Users</div>
                  <div className="wwanalytics-ops-value">{stats.onboarded}</div>
                </div>
                <div className="wwanalytics-ops-row">
                  <div className="wwanalytics-ops-label">Suspended Users</div>
                  <div className="wwanalytics-ops-value">{stats.suspended}</div>
                </div>
                <div className="wwanalytics-ops-row">
                  <div className="wwanalytics-ops-label">Total Challenges</div>
                  <div className="wwanalytics-ops-value">{stats.totalChallenges}</div>
                </div>
                <div className="wwanalytics-ops-row">
                  <div className="wwanalytics-ops-label">Total Business Partners</div>
                  <div className="wwanalytics-ops-value">{stats.totalBP}</div>
                </div>
                <div className="wwanalytics-ops-row">
                  <div className="wwanalytics-ops-label">Approved Business Partners</div>
                  <div className="wwanalytics-ops-value">{stats.approvedBP}</div>
                </div>
                <div className="wwanalytics-ops-row">
                  <div className="wwanalytics-ops-label">Pending BP Applications</div>
                  <div className="wwanalytics-ops-value">{stats.pendingBP}</div>
                </div>
              </div>
            </section>
          </div>
        </>
      )}
    </div>
  );
}

export default Analytics;
