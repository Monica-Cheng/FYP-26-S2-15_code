import React, { useState, useEffect } from 'react';
import { db } from '../firebase';
import { collection, getDocs } from 'firebase/firestore';
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

const isFiniteNumber = (v) => v !== undefined && v !== null && v !== '' && Number.isFinite(Number(v));

// Rounds to one decimal only when a fraction actually appears, so whole
// numbers don't grow a trailing ".0".
const average = (items, key) => {
  const valid = items.filter(item => isFiniteNumber(item[key])).map(item => Number(item[key]));
  if (valid.length === 0) return null;
  const mean = valid.reduce((sum, v) => sum + v, 0) / valid.length;
  return Math.round(mean * 10) / 10;
};

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

  useEffect(() => {
    const fetch = async () => {
      try {
        const [usersSnap, plansSnap, exSnap, bpSnap, chSnap, postsSnap] = await Promise.all([
          getDocs(collection(db, 'users')),
          getDocs(collection(db, 'plans')),
          getDocs(collection(db, 'exercises')),
          getDocs(collection(db, 'businessPartners')),
          getDocs(collection(db, 'challenges')),
          getDocs(collection(db, 'posts')),
        ]);
        const users = usersSnap.docs.map(d => d.data());
        const exercises = exSnap.docs.map(d => d.data());
        const challenges = chSnap.docs.map(d => d.data());
        const posts = postsSnap.docs.map(d => d.data());

        // Level distribution — only levels actually present in the data,
        // sorted numerically (same "no hardcoded list" approach as Users.js).
        const levelCounts = {};
        users.forEach(u => {
          const lvl = u.level || 1;
          levelCounts[lvl] = (levelCounts[lvl] || 0) + 1;
        });
        const levelDistribution = Object.keys(levelCounts)
          .map(Number)
          .sort((a, b) => a - b)
          .map(lvl => ({ label: `Lvl ${lvl}`, value: levelCounts[lvl] }));

        const difficultyCounts = { Beginner: 0, Intermediate: 0, Advanced: 0 };
        exercises.forEach(e => {
          const diff = e.difficulty || 'Beginner';
          difficultyCounts[diff] = (difficultyCounts[diff] || 0) + 1;
        });

        const challengeTypeCounts = {};
        challenges.forEach(c => {
          const type = c.type || 'Uncategorized';
          challengeTypeCounts[type] = (challengeTypeCounts[type] || 0) + 1;
        });

        // A "meal post" is defined by actually carrying nutrition data, not by
        // a guessed `type` string — some posts may not log calories at all.
        const mealPosts = posts.filter(p => isFiniteNumber(p.calories));
        const totalReactions = posts.reduce((sum, p) => sum + (Number(p.reactionCount) || 0), 0);
        const totalComments = posts.reduce((sum, p) => sum + (Number(p.commentCount) || 0), 0);

        // Recent Activity — only from collections/fields that reliably carry
        // a real timestamp. Plans and business partner docs may or may not
        // have createdAt depending on how they were created, so each source
        // is included opportunistically rather than assumed present; user
        // documents have no registration timestamp anywhere in the app, so
        // "recent registrations" is intentionally not offered here.
        const events = [];
        posts.forEach(p => {
          const date = toDate(p.createdAt);
          if (date) {
            events.push({
              date,
              icon: '📝',
              text: `${p.authorName || 'A user'} posted${p.foodName ? ` "${p.foodName}"` : ''}`,
            });
          }
        });
        plansSnap.docs.forEach(d => {
          const data = d.data();
          const date = toDate(data.createdAt);
          if (date) {
            events.push({ date, icon: '📋', text: `New plan created: "${data.name || 'Untitled plan'}"` });
          }
        });
        bpSnap.docs.forEach(d => {
          const data = d.data();
          const date = toDate(data.createdAt);
          if (date) {
            events.push({
              date,
              icon: '🤝',
              text: `New business partner application: ${data.displayName || data.businessName || data.email || 'Unknown'}`,
            });
          }
        });
        events.sort((a, b) => b.date - a.date);
        const recentActivity = events.slice(0, 8).map(e => ({ ...e, dateLabel: formatDate(e.date) }));

        setStats({
          totalUsers: usersSnap.size,
          totalPlans: plansSnap.size,
          totalExercises: exSnap.size,
          totalBP: bpSnap.size,
          totalChallenges: chSnap.size,
          approvedBP: bpSnap.docs.filter(d => d.data().status === 'approved').length,
          pendingBP: bpSnap.docs.filter(d => d.data().status === 'pending').length,
          healthConnected: users.filter(u => u.healthConnected).length,
          onboarded: users.filter(u => u.onboardingComplete).length,
          suspended: users.filter(u => u.accountStatus === 'suspended').length,
          premiumUsers: users.filter(u => u.isPremium).length,
          levelDistribution,
          difficultyCounts,
          challengeTypeCounts,
          totalPosts: postsSnap.size,
          totalMealPosts: mealPosts.length,
          totalReactions,
          totalComments,
          avgCalories: average(mealPosts, 'calories'),
          avgProtein: average(mealPosts, 'proteinG'),
          avgCarbs: average(mealPosts, 'carbsG'),
          avgFat: average(mealPosts, 'fatG'),
          recentActivity,
        });
      } catch (err) {
        console.error(err);
      }
      setLoading(false);
    };
    fetch();
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

  // Only surfaces sentences the loaded data can actually support — nothing
  // here is a guess, each is a direct percentage of already-fetched fields.
  const insights = stats && stats.totalUsers > 0 ? [
    `${onboardedPct}% of registered users have completed onboarding.`,
    `${healthPct}% of users have connected health data.`,
    `${activePct}% of users are currently active.`,
    `${premiumPct}% of users are currently premium.`,
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
        subtitle={loading ? 'Loading analytics…' : 'Platform overview — live from Firebase'}
        actions={!loading && stats && (
          <button className="wwa-btn wwa-btn-sm wwa-btn-success" onClick={handleExport}>
            📤 Export to Excel
          </button>
        )}
      />

      {loading ? (
        <div className="wwa-stats-grid">
          {Array.from({ length: 10 }).map((_, i) => <SkeletonBlock key={i} height={110} />)}
        </div>
      ) : (
        <>
          <div className="wwa-stats-grid">
            {cards.map(card => (
              <StatCard key={card.label} label={card.label} value={card.value} sub={card.sub} icon={card.icon} color={card.color} />
            ))}
          </div>

          <div className="wwa-charts-grid">
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
                { label: 'Active', value: stats.totalUsers - stats.suspended, color: STATUS_GREEN },
                { label: 'Suspended', value: stats.suspended, color: STATUS_RED },
              ]}
            />
            <DonutChart
              title="Health Connected"
              data={[
                { label: 'Connected', value: stats.healthConnected, color: STATUS_GREEN },
                { label: 'Not Connected', value: stats.totalUsers - stats.healthConnected, color: NEUTRAL_GRAY },
              ]}
            />
            {stats.levelDistribution.length > 0 && (
              <BarChart title="User Level Distribution" data={stats.levelDistribution} color={BRAND_PURPLE} />
            )}
          </div>

          {contentCards.length > 0 && (
            <div className="wwa-panel">
              <div className="wwa-panel-title">Content Analytics</div>
              <div className="wwa-panel-subtitle">Derived from the posts collection</div>
              <div className="wwa-stats-grid">
                {contentCards.map(card => (
                  <StatCard key={card.label} label={card.label} value={card.value} icon={card.icon} color={card.color} />
                ))}
              </div>
            </div>
          )}

          <div className="wwa-insights-grid">
            <div className="wwa-panel">
              <div className="wwa-panel-title">Platform Insights</div>
              <div className="wwa-panel-subtitle">Automatically generated from current data</div>
              {insights.length > 0 ? (
                insights.map(text => (
                  <div key={text} className="wwa-insight-row">
                    <span className="wwa-insight-icon">💡</span>
                    <span>{text}</span>
                  </div>
                ))
              ) : (
                <EmptyState icon="💡" message="Not enough data yet to generate insights." />
              )}
            </div>

            <div className="wwa-panel wwa-attention-panel">
              <div className="wwa-panel-title">Needs Attention</div>
              <div className="wwa-panel-subtitle">Actionable items for the admin team</div>
              {attentionItems.length > 0 ? (
                attentionItems.map(text => (
                  <div key={text} className="wwa-attention-row">
                    <span>{text}</span>
                  </div>
                ))
              ) : (
                <EmptyState icon="✅" message="Nothing needs attention right now." />
              )}
            </div>
          </div>

          <div className="wwa-panel">
            <div className="wwa-panel-title">Recent Activity</div>
            <div className="wwa-panel-subtitle">Latest timestamped events across the platform</div>
            {stats.recentActivity.length > 0 ? (
              stats.recentActivity.map((event, i) => (
                <div key={i} className="wwa-recent-row">
                  <span className="wwa-recent-icon">{event.icon}</span>
                  <span className="wwa-recent-text">{event.text}</span>
                  <span className="wwa-recent-date">{event.dateLabel}</span>
                </div>
              ))
            ) : (
              <EmptyState icon="🕒" message="No recent activity with a reliable timestamp yet." />
            )}
          </div>
        </>
      )}
    </div>
  );
}

export default Analytics;
