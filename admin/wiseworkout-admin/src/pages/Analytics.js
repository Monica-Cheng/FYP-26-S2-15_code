import React, { useState, useEffect } from 'react';
import { functions } from '../firebase';
import { httpsCallable } from 'firebase/functions';
import * as XLSX from 'xlsx';
import AdminStyles, { COLORS } from '../styles/AdminStyles';
import PageHeader from '../components/ui/PageHeader';
import SkeletonBlock from '../components/ui/SkeletonBlock';
import EmptyState from '../components/ui/EmptyState';
import DonutChart from '../components/ui/DonutChart';
import BarChart from '../components/ui/BarChart';
import { toDate, formatDate } from '../utils/dateUtils';

// Reuses the same green/red/purple/gray already used by Badge across the
// dashboard (Users.js, UserDetailPanel.js) so chart colors match table badges.
const STATUS_GREEN = '#1a9e6a';
const STATUS_RED = '#cc3333';
const BRAND_PURPLE = '#6c63ff';
const NEUTRAL_GRAY = '#9ca3af';

const pct = (num, den) => (den > 0 ? Math.round((num / den) * 100) : 0);

function StatCard({ label, value, sub, icon, color }) {
  return (
    <div className="wwa-stat-card" style={{ '--accent': color.base, '--accent-light': color.light }}>
      <div className="wwa-stat-top">
        <span className="wwa-stat-title">{label}</span>
        <span className="wwa-stat-icon">{icon}</span>
      </div>
      <div className="wwa-stat-value">{value}</div>
      {sub && <div className="wwa-stat-sub">{sub}</div>}
    </div>
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
        const adminGetAnalyticsDashboard = httpsCallable(
          functions,
          'adminGetAnalyticsDashboard'
        );
  
        const result = await adminGetAnalyticsDashboard();
        const receivedStats = result.data?.stats;
  
        if (!receivedStats) {
          throw new Error('Analytics data was missing from the server response.');
        }
  
        const recentActivity = Array.isArray(receivedStats.recentActivity)
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
          levelDistribution: Array.isArray(receivedStats.levelDistribution)
            ? receivedStats.levelDistribution
            : [],
          difficultyCounts:
            receivedStats.difficultyCounts &&
            typeof receivedStats.difficultyCounts === 'object'
              ? receivedStats.difficultyCounts
              : {},
          challengeTypeCounts:
            receivedStats.challengeTypeCounts &&
            typeof receivedStats.challengeTypeCounts === 'object'
              ? receivedStats.challengeTypeCounts
              : {},
          recentActivity,
        });
      } catch (err) {
        console.error('Failed to load analytics:', err);
  
        const detail = err?.code ? ` (${err.code})` : '';
  
        setLoadError(
          `Failed to load analytics.${detail}`
        );
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

  const cards = stats ? [
    { label: 'Total Users', value: stats.totalUsers, icon: '👥', color: COLORS.primary },
    {
      label: 'Onboarded Users', value: stats.onboarded, icon: '🧭', color: COLORS.cyan,
      sub: `${stats.onboarded} / ${stats.totalUsers} (${onboardedPct}%)`, pct: onboardedPct,
    },
    {
      label: 'Health Connected', value: stats.healthConnected, icon: '❤️', color: COLORS.green,
      sub: `${stats.healthConnected} / ${stats.totalUsers} (${healthPct}%)`, pct: healthPct,
    },
    {
      label: 'Premium Users', value: stats.premiumUsers, icon: '⭐', color: COLORS.amber,
      sub: `${stats.premiumUsers} / ${stats.totalUsers} (${premiumPct}%)`, pct: premiumPct,
    },
    {
      label: 'Suspended Users', value: stats.suspended, icon: '🚫', color: COLORS.red,
      sub: `${stats.suspended} / ${stats.totalUsers} (${suspendedPct}%)`, pct: suspendedPct,
    },
    { label: 'Total Plans', value: stats.totalPlans, icon: '📋', color: COLORS.primary },
    { label: 'Total Exercises', value: stats.totalExercises, icon: '💪', color: COLORS.green },
    { label: 'Total Challenges', value: stats.totalChallenges, icon: '🏆', color: COLORS.amber },
    { label: 'Total Business Partners', value: stats.totalBP, icon: '🤝', color: COLORS.cyan },
    { label: 'Approved BPs', value: stats.approvedBP, icon: '✅', color: COLORS.green },
    { label: 'Pending BP Applications', value: stats.pendingBP, icon: '⏳', color: COLORS.red },
  ] : [];

  const contentCards = stats && stats.totalPosts > 0 ? [
    { label: 'Total Posts', value: stats.totalPosts, icon: '📝', color: COLORS.primary },
    { label: 'Total Meal Posts', value: stats.totalMealPosts, icon: '🍽️', color: COLORS.green },
    { label: 'Total Reactions', value: stats.totalReactions, icon: '❤️', color: COLORS.red },
    { label: 'Total Comments', value: stats.totalComments, icon: '💬', color: COLORS.cyan },
    {
      label: 'Avg Calories / Meal Post', value: stats.avgCalories !== null ? stats.avgCalories : '—',
      icon: '🔥', color: COLORS.amber,
    },
    {
      label: 'Avg Protein / Carbs / Fat',
      value: [stats.avgProtein, stats.avgCarbs, stats.avgFat].every(v => v === null)
        ? '—'
        : `${stats.avgProtein ?? '—'}g / ${stats.avgCarbs ?? '—'}g / ${stats.avgFat ?? '—'}g`,
      icon: '🥗', color: COLORS.green,
    },
  ] : [];

  
  // Only zero-value item that still warrants a callout is "no premium
  // users" — every other zero is a good outcome and is omitted.
  const attentionItems = [];
  if (stats) {
    const notConnected = stats.totalUsers - stats.healthConnected;
    const notOnboarded = stats.totalUsers - stats.onboarded;
    if (notConnected > 0) attentionItems.push(`⚠️ ${notConnected} user${notConnected === 1 ? '' : 's'} have not connected health data`);
    if (stats.suspended > 0) attentionItems.push(`🚫 ${stats.suspended} user${stats.suspended === 1 ? '' : 's'} currently suspended`);
    if (stats.pendingBP > 0) attentionItems.push(`⏳ ${stats.pendingBP} business partner application${stats.pendingBP === 1 ? '' : 's'} pending review`);
    if (notOnboarded > 0) attentionItems.push(`🧭 ${notOnboarded} user${notOnboarded === 1 ? '' : 's'} have not completed onboarding`);
    if (stats.totalUsers > 0 && stats.premiumUsers === 0) attentionItems.push('⭐ No premium users currently registered');
  }

  // Exports exactly what's on screen — the same stats object backing the
  // stat cards, insights, and Needs Attention — organized into one sheet per
  // data area, skipping any sheet whose underlying collection has no data.
  const handleExport = () => {
    if (!stats) return;
    const workbook = XLSX.utils.book_new();

    const summaryRows = cards.map(c => ({ Metric: c.label, Value: c.value, Percentage: c.pct !== undefined ? `${c.pct}%` : '' }));
    const summarySheet = XLSX.utils.json_to_sheet(summaryRows);
    summarySheet['!cols'] = [{ wch: 28 }, { wch: 12 }, { wch: 12 }];
    XLSX.utils.book_append_sheet(workbook, summarySheet, 'Summary');

    const freeUsers = stats.totalUsers - stats.premiumUsers;
    const activeUsers = stats.totalUsers - stats.suspended;
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
      ...stats.levelDistribution.map(l => ({ Metric: l.label, Value: l.value })),
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
          .map(([diff, count]) => ({ Metric: diff, Value: count })),
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

    if (attentionItems.length > 0) {
      const attentionSheet = XLSX.utils.json_to_sheet(attentionItems.map(item => ({ Item: item })));
      attentionSheet['!cols'] = [{ wch: 50 }];
      XLSX.utils.book_append_sheet(workbook, attentionSheet, 'Needs Attention');
    }

    XLSX.writeFile(workbook, 'WiseWorkout_Analytics.xlsx');
  };

  return (
    <div>
      <AdminStyles />
  
      <PageHeader
        title="Analytics"
        subtitle={
          loading
            ? 'Loading analytics…'
            : 'Platform overview — live from Firebase'
        }
        actions={
          !loading &&
          stats && (
            <button
              className="wwa-btn wwa-btn-sm wwa-btn-success"
              onClick={handleExport}
            >
              📤 Export to Excel
            </button>
          )
        }
      />
  
      {loading ? (
        <div className="wwa-stats-grid">
          {Array.from({ length: 10 }).map((_, i) => (
            <SkeletonBlock key={i} height={110} />
          ))}
        </div>
      ) : loadError ? (
        <div className="wwa-panel">
          <div className="wwa-alert-error">
            {loadError}
          </div>
        </div>
      ) : !stats ? (
        <div className="wwa-panel">
          <EmptyState
            icon="📊"
            title="No analytics available"
            message="The analytics data could not be loaded."
          />
        </div>
      ) : (
        <>
          <div className="wwa-stats-grid">
            {cards.map(card => (
              <StatCard
                key={card.label}
                label={card.label}
                value={card.value}
                sub={card.sub}
                icon={card.icon}
                color={card.color}
              />
            ))}
          </div>
  
          <div className="wwa-charts-grid">
            <DonutChart
              title="Premium vs Free Users"
              data={[
                {
                  label: 'Premium',
                  value: stats.premiumUsers,
                  color: BRAND_PURPLE,
                },
                {
                  label: 'Free',
                  value:
                    stats.totalUsers -
                    stats.premiumUsers,
                  color: NEUTRAL_GRAY,
                },
              ]}
            />
  
            <DonutChart
              title="Active vs Suspended Users"
              data={[
                {
                  label: 'Active',
                  value:
                    stats.totalUsers -
                    stats.suspended,
                  color: STATUS_GREEN,
                },
                {
                  label: 'Suspended',
                  value: stats.suspended,
                  color: STATUS_RED,
                },
              ]}
            />
  
            <DonutChart
              title="Health Connected"
              data={[
                {
                  label: 'Connected',
                  value: stats.healthConnected,
                  color: STATUS_GREEN,
                },
                {
                  label: 'Not Connected',
                  value:
                    stats.totalUsers -
                    stats.healthConnected,
                  color: NEUTRAL_GRAY,
                },
              ]}
            />
  
            {stats.levelDistribution.length > 0 && (
              <BarChart
                title="User Level Distribution"
                data={stats.levelDistribution}
                color={BRAND_PURPLE}
              />
            )}
          </div>
  
          {contentCards.length > 0 && (
            <div className="wwa-panel">
              <div className="wwa-panel-title">
                Content Analytics
              </div>
  
              <div className="wwa-panel-subtitle">
                Derived from the posts collection
              </div>
  
              <div className="wwa-stats-grid">
                {contentCards.map(card => (
                  <StatCard
                    key={card.label}
                    label={card.label}
                    value={card.value}
                    icon={card.icon}
                    color={card.color}
                  />
                ))}
              </div>
            </div>
          )}
  
          
        </>
      )}
    </div>
  );
  }
export default Analytics;
