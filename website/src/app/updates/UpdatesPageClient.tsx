"use client";

import { useState, useEffect, type FormEvent } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { useRouter } from "next/navigation";
import {
  ChevronDown,
  Lock,
  Plus,
  X,
  Pencil,
  Trash2,
  CheckCircle2,
  Calendar,
  Users,
  BookOpen,
  ClipboardList,
  AlertCircle,
  Loader2,
} from "lucide-react";
import FadeInUp from "@/components/animations/FadeInUp";
import { StaggerChildren, StaggerItem } from "@/components/animations/StaggerChildren";
import { normalizeWeekLabel } from "@/lib/week-label";
import { siteConfig } from "@/content/site-config";
import type { MeetingMinute, DiaryEntry } from "./page";

type ActiveTab = "minutes" | "diaries";
type AdminFormTab = "minutes" | "diary";
type Toast = { type: "success" | "error"; message: string } | null;

function formatDate(dateStr: string): string {
  return new Date(dateStr).toLocaleDateString("en-SG", {
    day: "numeric",
    month: "long",
    year: "numeric",
  });
}

function AccordionMinute({
  minute,
  onEdit,
  onDelete,
}: {
  minute: MeetingMinute;
  onEdit: (minute: MeetingMinute) => void;
  onDelete: (minute: MeetingMinute) => void;
}) {
  const [open, setOpen] = useState(false);

  const detailSections = [
    {
      title: "Meeting Objectives",
      items: minute.meeting_objectives ?? [],
    },
    {
      title: "Agenda",
      items: minute.agenda ?? [],
    },
    {
      title: "Meeting Notes",
      body: minute.notes,
    },
    {
      title: "Key Decisions Made",
      items: minute.key_decisions ?? [],
    },
    {
      title: "Action Items",
      items: minute.action_items ?? [],
    },
  ];

  return (
    <div className="overflow-hidden rounded-card border border-white/10 bg-midnight">
      <div className="flex items-center justify-between gap-4 px-6 py-5">
        <div className="flex flex-col gap-1.5">
          <div className="flex flex-wrap items-center gap-3">
            <span className="flex items-center gap-1.5 text-meta text-fog">
              <Calendar className="h-3.5 w-3.5" />
              {formatDate(minute.meeting_date)}
            </span>
            {minute.meeting_time && (
              <span className="rounded-full border border-white/10 px-3 py-0.5 text-meta text-silver">
                {minute.meeting_time}
              </span>
            )}
          </div>
          {minute.attendees?.length > 0 && (
            <p className="flex items-center gap-1.5 text-ui text-white">
              <Users className="h-3.5 w-3.5 text-fog" />
              {minute.attendees.join(", ")}
            </p>
          )}
        </div>
        <div className="flex items-center gap-1">
          <button
            type="button"
            onClick={() => onEdit(minute)}
            className="rounded-full p-2 text-fog transition-colors hover:bg-white/[0.06] hover:text-white"
            title="Edit meeting minutes"
            aria-label={`Edit ${minute.week_label} meeting minutes`}
          >
            <Pencil className="h-4 w-4" />
          </button>
          <button
            type="button"
            onClick={() => onDelete(minute)}
            className="rounded-full p-2 text-fog transition-colors hover:bg-white/[0.06] hover:text-alert-red"
            title="Delete meeting minutes"
            aria-label={`Delete ${minute.week_label} meeting minutes`}
          >
            <Trash2 className="h-4 w-4" />
          </button>
          <button
            type="button"
            onClick={() => setOpen(!open)}
            className="rounded-full p-2 text-fog transition-colors hover:bg-white/[0.06] hover:text-white"
            aria-expanded={open}
            aria-label={open ? "Collapse meeting minutes" : "Expand meeting minutes"}
          >
            <motion.div
              animate={{ rotate: open ? 180 : 0 }}
              transition={{ duration: 0.2 }}
              className="flex-shrink-0"
            >
              <ChevronDown className="h-5 w-5" />
            </motion.div>
          </button>
        </div>
      </div>

      <AnimatePresence initial={false}>
        {open && (
          <motion.div
            key="content"
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: "auto", opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.3, ease: [0.22, 1, 0.36, 1] }}
            style={{ overflow: "hidden" }}
          >
            <div className="space-y-6 border-t border-white/10 px-6 py-6">
              {detailSections.map((section) => {
                if (section.items && section.items.length > 0) {
                  return (
                    <div key={section.title}>
                      <h4 className="mb-2 text-meta text-fog">{section.title}</h4>
                      <ul className="space-y-2">
                        {section.items.map((item, i) => (
                          <li key={i} className="flex items-start gap-2.5 text-ui text-silver">
                            <CheckCircle2 className="mt-0.5 h-4 w-4 flex-shrink-0 text-fog" />
                            {item}
                          </li>
                        ))}
                      </ul>
                    </div>
                  );
                }

                if (section.body) {
                  return (
                    <div key={section.title}>
                      <h4 className="mb-2 text-meta text-fog">{section.title}</h4>
                      <p className="whitespace-pre-line text-ui leading-relaxed text-silver">
                        {section.body}
                      </p>
                    </div>
                  );
                }

                return null;
              })}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

function DiaryCard({
  entry,
  onEdit,
  onDelete,
}: {
  entry: DiaryEntry;
  onEdit: (entry: DiaryEntry) => void;
  onDelete: (entry: DiaryEntry) => void;
}) {
  const [open, setOpen] = useState(false);

  return (
    <div className="overflow-hidden rounded-card border border-white/10 bg-midnight">
      <div className="flex items-center justify-between gap-4 px-6 py-5">
        <h4 className="text-heading-sm font-semibold text-white">{entry.title}</h4>
        <div className="flex items-center gap-1">
          <button
            type="button"
            onClick={() => onEdit(entry)}
            className="rounded-full p-2 text-fog transition-colors hover:bg-white/[0.06] hover:text-white"
            title="Edit entry"
            aria-label={`Edit ${entry.title}`}
          >
            <Pencil className="h-4 w-4" />
          </button>
          <button
            type="button"
            onClick={() => onDelete(entry)}
            className="rounded-full p-2 text-fog transition-colors hover:bg-white/[0.06] hover:text-alert-red"
            title="Delete entry"
            aria-label={`Delete ${entry.title}`}
          >
            <Trash2 className="h-4 w-4" />
          </button>
          <button
            type="button"
            onClick={() => setOpen(!open)}
            className="rounded-full p-2 text-fog transition-colors hover:bg-white/[0.06] hover:text-white"
            aria-expanded={open}
            aria-label={open ? "Collapse diary entry" : "Expand diary entry"}
          >
            <motion.div
              animate={{ rotate: open ? 180 : 0 }}
              transition={{ duration: 0.2 }}
              className="flex-shrink-0"
            >
              <ChevronDown className="h-5 w-5" />
            </motion.div>
          </button>
        </div>
      </div>

      <AnimatePresence initial={false}>
        {open && (
          <motion.div
            key="content"
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: "auto", opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            transition={{ duration: 0.3, ease: [0.22, 1, 0.36, 1] }}
            style={{ overflow: "hidden" }}
          >
            <div className="border-t border-white/10 px-6 py-6">
              <p className="whitespace-pre-line text-ui leading-relaxed text-silver">
                {entry.body}
              </p>
              <p className="mt-4 text-meta text-fog">{formatDate(entry.created_at)}</p>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

/* The empty state is an invitation, not an apology. */
function EmptyState({ title, body }: { title: string; body: string }) {
  return (
    <div className="rounded-card border border-white/10 bg-midnight px-6 py-14 text-center">
      <p className="text-heading-sm font-semibold text-white">{title}</p>
      <p className="mx-auto mt-3 max-w-[52ch] text-lede text-silver">{body}</p>
    </div>
  );
}

export default function UpdatesPageClient({
  meetingMinutes,
  diaryEntries,
}: {
  meetingMinutes: MeetingMinute[];
  diaryEntries: DiaryEntry[];
}) {
  const router = useRouter();

  const [activeTab, setActiveTab] = useState<ActiveTab>("minutes");
  const [showAdminModal, setShowAdminModal] = useState(false);
  const [adminUnlocked, setAdminUnlocked] = useState(false);
  const [passwordInput, setPasswordInput] = useState("");
  const [adminPassword, setAdminPassword] = useState("");
  const [verifying, setVerifying] = useState(false);
  const [passwordError, setPasswordError] = useState("");
  const [adminFormTab, setAdminFormTab] = useState<AdminFormTab>("minutes");
  const [submitting, setSubmitting] = useState(false);
  const [toast, setToast] = useState<Toast>(null);

  // Meeting minutes form
  const [mmWeek, setMmWeek] = useState("");
  const [mmDate, setMmDate] = useState("");
  const [mmTime, setMmTime] = useState("");
  const [mmAttendees, setMmAttendees] = useState("");
  const [mmObjectives, setMmObjectives] = useState("");
  const [mmAgenda, setMmAgenda] = useState("");
  const [mmNotes, setMmNotes] = useState("");
  const [mmKeyDecisions, setMmKeyDecisions] = useState("");
  const [mmActions, setMmActions] = useState("");
  const [editingMinuteId, setEditingMinuteId] = useState<string | null>(null);

  // Diary entry form
  const [deWeek, setDeWeek] = useState("");
  const [deName, setDeName] = useState("");
  const [deBody, setDeBody] = useState("");
  const [editingDiaryId, setEditingDiaryId] = useState<string | null>(null);

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 3500);
    return () => clearTimeout(t);
  }, [toast]);

  function resetDiaryForm() {
    setDeWeek("");
    setDeName("");
    setDeBody("");
    setEditingDiaryId(null);
  }

  function resetMinutesForm() {
    setMmWeek("");
    setMmDate("");
    setMmTime("");
    setMmAttendees("");
    setMmObjectives("");
    setMmAgenda("");
    setMmNotes("");
    setMmKeyDecisions("");
    setMmActions("");
    setEditingMinuteId(null);
  }

  function openEditDiaryModal(entry: DiaryEntry) {
    setEditingDiaryId(entry.id);
    setDeWeek(entry.week_label);
    setDeName(entry.title);
    setDeBody(entry.body);
    setAdminFormTab("diary");
    setShowAdminModal(true);
  }

  function openNewDiaryModal() {
    resetDiaryForm();
    setAdminFormTab("diary");
    setShowAdminModal(true);
  }

  function openEditMinuteModal(minute: MeetingMinute) {
    setEditingMinuteId(minute.id);
    setMmWeek(minute.week_label);
    setMmDate(minute.meeting_date);
    setMmTime(minute.meeting_time ?? "");
    setMmAttendees((minute.attendees ?? []).join(", "));
    setMmObjectives((minute.meeting_objectives ?? []).join("\n"));
    setMmAgenda((minute.agenda ?? []).join("\n"));
    setMmNotes(minute.notes);
    setMmKeyDecisions((minute.key_decisions ?? []).join("\n"));
    setMmActions((minute.action_items ?? []).join("\n"));
    setAdminFormTab("minutes");
    setShowAdminModal(true);
  }

  function openNewMinutesModal() {
    resetMinutesForm();
    setAdminFormTab("minutes");
    setShowAdminModal(true);
  }

  function closeAdminModal() {
    setShowAdminModal(false);
    setAdminUnlocked(false);
    setPasswordInput("");
    setAdminPassword("");
    setPasswordError("");
    resetMinutesForm();
    resetDiaryForm();
  }

  /* The password is verified on the server and then held in memory for this
     session only. It is never read from the environment on the client — that
     would put it in the browser bundle. */
  async function handlePasswordSubmit(e: FormEvent) {
    e.preventDefault();
    setVerifying(true);
    setPasswordError("");

    try {
      const res = await fetch("/api/admin/verify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ password: passwordInput }),
      });

      if (res.ok) {
        setAdminPassword(passwordInput);
        setAdminUnlocked(true);
        setPasswordInput("");
        return;
      }

      const d = (await res.json().catch(() => ({}))) as { error?: string };
      setPasswordError(
        res.status === 503
          ? (d.error ?? "Admin is not configured on this server.")
          : "Incorrect password. Try again.",
      );
    } catch {
      setPasswordError("Network error. Please try again.");
    } finally {
      setVerifying(false);
    }
  }

  async function handleMinutesSubmit(e: FormEvent) {
    e.preventDefault();
    setSubmitting(true);
    try {
      const isEditing = Boolean(editingMinuteId);
      const res = await fetch("/api/admin/meeting-minutes", {
        method: isEditing ? "PUT" : "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          id: editingMinuteId,
          password: adminPassword,
          week_label: mmWeek,
          meeting_date: mmDate,
          meeting_time: mmTime,
          attendees: mmAttendees,
          meeting_objectives: mmObjectives,
          agenda: mmAgenda,
          notes: mmNotes,
          key_decisions: mmKeyDecisions,
          action_items: mmActions,
        }),
      });
      if (res.ok) {
        setToast({
          type: "success",
          message: isEditing ? "Meeting minutes updated." : "Meeting minutes saved.",
        });
        closeAdminModal();
        router.refresh();
      } else {
        const d = (await res.json()) as { error?: string };
        setToast({ type: "error", message: d.error ?? "Failed to save." });
      }
    } catch {
      setToast({ type: "error", message: "Network error. Please try again." });
    } finally {
      setSubmitting(false);
    }
  }

  async function handleDeleteDiary(entry: DiaryEntry) {
    if (!window.confirm(`Delete ${entry.title}'s diary entry? This cannot be undone.`)) {
      return;
    }

    setSubmitting(true);
    try {
      const res = await fetch("/api/admin/diary-entry", {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          id: entry.id,
          password: adminPassword,
        }),
      });

      if (res.ok) {
        setToast({ type: "success", message: "Diary entry deleted." });
        router.refresh();
      } else {
        const d = (await res.json()) as { error?: string };
        setToast({ type: "error", message: d.error ?? "Failed to delete." });
      }
    } catch {
      setToast({ type: "error", message: "Network error. Please try again." });
    } finally {
      setSubmitting(false);
    }
  }

  async function handleDeleteMinute(minute: MeetingMinute) {
    if (!window.confirm(`Delete meeting minutes for ${minute.week_label} on ${formatDate(minute.meeting_date)}? This cannot be undone.`)) {
      return;
    }

    setSubmitting(true);
    try {
      const res = await fetch("/api/admin/meeting-minutes", {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          id: minute.id,
          password: adminPassword,
        }),
      });

      if (res.ok) {
        setToast({ type: "success", message: "Meeting minutes deleted." });
        router.refresh();
      } else {
        const d = (await res.json()) as { error?: string };
        setToast({ type: "error", message: d.error ?? "Failed to delete." });
      }
    } catch {
      setToast({ type: "error", message: "Network error. Please try again." });
    } finally {
      setSubmitting(false);
    }
  }

  async function handleDiarySubmit(e: FormEvent) {
    e.preventDefault();
    setSubmitting(true);
    try {
      const isEditing = Boolean(editingDiaryId);
      const res = await fetch("/api/admin/diary-entry", {
        method: isEditing ? "PUT" : "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          id: editingDiaryId,
          password: adminPassword,
          week_label: deWeek,
          name: deName,
          body: deBody,
        }),
      });
      if (res.ok) {
        setToast({
          type: "success",
          message: isEditing ? "Diary entry updated." : "Diary entry saved.",
        });
        closeAdminModal();
        router.refresh();
      } else {
        const d = (await res.json()) as { error?: string };
        setToast({ type: "error", message: d.error ?? "Failed to save." });
      }
    } catch {
      setToast({ type: "error", message: "Network error. Please try again." });
    } finally {
      setSubmitting(false);
    }
  }

  // Group diary entries by week_label, newest weeks first
  const groupedDiaries = diaryEntries.reduce<Record<string, DiaryEntry[]>>((acc, entry) => {
    const normalizedWeek = normalizeWeekLabel(entry.week_label);
    if (!acc[normalizedWeek]) acc[normalizedWeek] = [];
    acc[normalizedWeek].push({
      ...entry,
      week_label: normalizedWeek,
    });
    return acc;
  }, {});
  const sortedWeeks = Object.keys(groupedDiaries).sort((a, b) => {
    const na = parseInt(a.replace(/\D/g, "")) || 0;
    const nb = parseInt(b.replace(/\D/g, "")) || 0;
    return nb - na;
  });

  const groupedMinutes = meetingMinutes.reduce<Record<string, MeetingMinute[]>>((acc, minute) => {
    const normalizedWeek = normalizeWeekLabel(minute.week_label);
    if (!acc[normalizedWeek]) acc[normalizedWeek] = [];
    acc[normalizedWeek].push({
      ...minute,
      week_label: normalizedWeek,
    });
    return acc;
  }, {});
  const sortedMinuteWeeks = Object.keys(groupedMinutes).sort((a, b) => {
    const na = parseInt(a.replace(/\D/g, "")) || 0;
    const nb = parseInt(b.replace(/\D/g, "")) || 0;
    return nb - na;
  });

  const inputCls =
    "w-full rounded-xl border border-silver bg-white px-4 py-2.5 text-ui text-ink placeholder-fog transition-colors focus:border-signal-blue focus:outline-none";
  const labelCls = "block text-meta font-medium text-carbon mb-1.5";

  return (
    <div className="bg-deep-indigo">
      {/* ── Header ───────────────────────────────────────────── */}
      <section className="px-6 pb-10 pt-14">
        <div className="mx-auto w-full max-w-[1200px]">
          <FadeInUp className="max-w-3xl">
            <p className="text-meta text-fog">
              {siteConfig.academic.group} · {siteConfig.academic.course} ·{" "}
              {siteConfig.academic.school} · {siteConfig.academic.year}
            </p>
            <h1 className="mt-4 text-display font-bold text-white">
              The project log, as it is written.
            </h1>
            <p className="mt-5 max-w-[62ch] text-lede text-silver">
              Meeting minutes and individual reflective diaries, published weekly and
              unedited. This is the same record our supervisor reads.
            </p>
          </FadeInUp>
        </div>
      </section>

      {/* ── Tab switcher — pill segmented control ────────────── */}
      <section className="px-6">
        <div className="mx-auto w-full max-w-[1200px]">
          <div className="inline-flex rounded-full border border-white/10 bg-midnight p-1">
            {(
              [
                { id: "minutes", label: "Meeting minutes", icon: ClipboardList },
                { id: "diaries", label: "Reflective diaries", icon: BookOpen },
              ] as const
            ).map(({ id, label, icon: Icon }) => (
              <button
                key={id}
                onClick={() => setActiveTab(id)}
                aria-pressed={activeTab === id}
                className={`inline-flex items-center gap-2 rounded-full px-5 py-2.5 text-ui font-medium transition-colors ${
                  activeTab === id
                    ? "bg-white text-ink"
                    : "text-silver hover:text-white"
                }`}
              >
                <Icon className="h-4 w-4" />
                {label}
              </button>
            ))}
          </div>
        </div>
      </section>

      {/* ── Tab content ──────────────────────────────────────── */}
      <section className="px-6 pb-20 pt-10">
        <div className="mx-auto w-full max-w-[1200px]">
          <AnimatePresence mode="wait">
            {activeTab === "minutes" && (
              <motion.div
                key="minutes"
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -10 }}
                transition={{ duration: 0.25 }}
              >
                {meetingMinutes.length === 0 ? (
                  <EmptyState
                    title="The first minute lands after our next meeting."
                    body="We meet weekly and publish the record the same week. Nothing is held back for a tidier version later."
                  />
                ) : (
                  <div className="space-y-12">
                    {sortedMinuteWeeks.map((week) => (
                      <div key={week}>
                        <h2 className="mb-4 flex items-center gap-4 text-meta text-fog">
                          {week}
                          <span className="h-px flex-1 bg-white/10" />
                        </h2>
                        <StaggerChildren className="flex flex-col gap-4">
                          {groupedMinutes[week].map((m) => (
                            <StaggerItem key={m.id}>
                              <AccordionMinute
                                minute={m}
                                onEdit={openEditMinuteModal}
                                onDelete={handleDeleteMinute}
                              />
                            </StaggerItem>
                          ))}
                        </StaggerChildren>
                      </div>
                    ))}
                  </div>
                )}
              </motion.div>
            )}

            {activeTab === "diaries" && (
              <motion.div
                key="diaries"
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -10 }}
                transition={{ duration: 0.25 }}
              >
                {sortedWeeks.length === 0 ? (
                  <EmptyState
                    title="Five diaries go up at the end of each week."
                    body="Each of us writes what we shipped, what broke, and what we would do differently. The first set publishes with week one."
                  />
                ) : (
                  <div className="space-y-12">
                    {sortedWeeks.map((week) => (
                      <div key={week}>
                        <h2 className="mb-4 flex items-center gap-4 text-meta text-fog">
                          {week}
                          <span className="h-px flex-1 bg-white/10" />
                        </h2>
                        <StaggerChildren className="flex flex-col gap-4">
                          {groupedDiaries[week].map((entry) => (
                            <StaggerItem key={entry.id}>
                              <DiaryCard
                                entry={entry}
                                onEdit={openEditDiaryModal}
                                onDelete={handleDeleteDiary}
                              />
                            </StaggerItem>
                          ))}
                        </StaggerChildren>
                      </div>
                    ))}
                  </div>
                )}
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </section>

      {/* ── Floating admin button ─────────────────────────────── */}
      <button
        type="button"
        onClick={() => {
          if (activeTab === "diaries") {
            openNewDiaryModal();
            return;
          }
          openNewMinutesModal();
        }}
        className="fixed bottom-8 right-8 z-30 inline-flex items-center gap-2 rounded-full bg-white px-5 py-3 text-ui font-semibold text-ink shadow-whisper transition-colors hover:bg-linen"
        aria-label="Open admin panel"
      >
        <Plus className="h-4 w-4" />
        Admin
      </button>

      {/* ── Admin modal ──────────────────────────────────────── */}
      <AnimatePresence>
        {showAdminModal && (
          <>
            {/* Backdrop */}
            <motion.div
              key="backdrop"
              className="fixed inset-0 z-[100] bg-deep-indigo/60"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={closeAdminModal}
            />

            {/* Panel */}
            <motion.div
              key="panel"
              className="fixed inset-x-4 bottom-4 top-4 z-[110] mx-auto flex max-w-lg flex-col overflow-hidden rounded-float border border-silver bg-white shadow-whisper sm:inset-x-auto sm:left-1/2 sm:w-full sm:-translate-x-1/2"
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: 8 }}
              transition={{ duration: 0.2, ease: [0.22, 1, 0.36, 1] }}
            >
              {/* Modal header */}
              <div className="flex items-center justify-between border-b border-silver px-6 py-4">
                <div className="flex items-center gap-2">
                  <Lock className="h-4 w-4 text-steel" />
                  <span className="text-ui font-semibold text-ink">Admin</span>
                </div>
                <button
                  type="button"
                  onClick={closeAdminModal}
                  aria-label="Close admin panel"
                  className="inline-flex h-9 w-9 items-center justify-center rounded-full border border-ink/50 text-ink transition-colors hover:bg-ink/[0.04]"
                >
                  <X className="h-4 w-4" />
                </button>
              </div>

              <div className="flex-1 overflow-y-auto px-6 py-6">
                {!adminUnlocked ? (
                  /* Password gate */
                  <form onSubmit={handlePasswordSubmit} className="flex flex-col gap-4">
                    <p className="text-lede text-carbon">
                      Enter the admin password to add or update entries.
                    </p>
                    <div>
                      <label className={labelCls} htmlFor="admin-pw">
                        Password
                      </label>
                      <input
                        id="admin-pw"
                        type="password"
                        value={passwordInput}
                        onChange={(e) => setPasswordInput(e.target.value)}
                        placeholder="Admin password"
                        required
                        autoFocus
                        className={inputCls}
                      />
                      {passwordError && (
                        <p className="mt-2 flex items-center gap-1.5 text-meta text-alert-red">
                          <AlertCircle className="h-3.5 w-3.5" />
                          {passwordError}
                        </p>
                      )}
                    </div>
                    {/* The one filled #007bff button on this surface */}
                    <button
                      type="submit"
                      disabled={verifying}
                      className="inline-flex items-center justify-center gap-2 rounded-full bg-signal-blue py-3 text-ui font-semibold text-white transition-colors hover:bg-[#0069d9] disabled:cursor-not-allowed disabled:opacity-60"
                    >
                      {verifying ? (
                        <>
                          <Loader2 className="h-4 w-4 animate-spin" />
                          Checking…
                        </>
                      ) : (
                        "Unlock"
                      )}
                    </button>
                  </form>
                ) : (
                  /* Admin forms */
                  <div className="flex flex-col gap-5">
                    {/* Form tab switcher */}
                    <div className="flex rounded-full border border-silver bg-linen p-1">
                      {(
                        [
                          { id: "minutes", label: "Meeting minutes" },
                          { id: "diary", label: "Diary entry" },
                        ] as const
                      ).map(({ id, label }) => (
                        <button
                          key={id}
                          type="button"
                          onClick={() => setAdminFormTab(id)}
                          aria-pressed={adminFormTab === id}
                          className={`flex-1 rounded-full py-2 text-meta font-medium transition-colors ${
                            adminFormTab === id
                              ? "bg-white text-ink shadow-whisper"
                              : "text-steel hover:text-ink"
                          }`}
                        >
                          {label}
                        </button>
                      ))}
                    </div>

                    <AnimatePresence mode="wait">
                      {adminFormTab === "minutes" ? (
                        <motion.form
                          key="mm-form"
                          onSubmit={handleMinutesSubmit}
                          initial={{ opacity: 0, x: -10 }}
                          animate={{ opacity: 1, x: 0 }}
                          exit={{ opacity: 0, x: 10 }}
                          transition={{ duration: 0.2 }}
                          className="flex flex-col gap-4"
                        >
                          <div className="rounded-xl border border-silver bg-linen px-4 py-3 text-meta leading-6 text-carbon">
                            {editingMinuteId
                              ? "You are editing an existing set of meeting minutes. Update the fields below and save your changes."
                              : "Create a new set of meeting minutes for the selected week."}
                          </div>
                          <div className="grid grid-cols-2 gap-3">
                            <div>
                              <label className={labelCls}>Week label</label>
                              <input
                                value={mmWeek}
                                onChange={(e) => setMmWeek(e.target.value)}
                                placeholder="e.g. Week 3"
                                required
                                className={inputCls}
                              />
                            </div>
                            <div>
                              <label className={labelCls}>Meeting date</label>
                              <input
                                type="date"
                                value={mmDate}
                                onChange={(e) => setMmDate(e.target.value)}
                                required
                                className={inputCls}
                              />
                            </div>
                          </div>
                          <div>
                            <label className={labelCls}>Meeting time</label>
                            <input
                              value={mmTime}
                              onChange={(e) => setMmTime(e.target.value)}
                              placeholder="e.g. 2:00 PM - 2:45 PM"
                              className={inputCls}
                            />
                          </div>
                          <div>
                            <label className={labelCls}>
                              Attendees{" "}
                              <span className="font-normal text-fog">(comma-separated)</span>
                            </label>
                            <input
                              value={mmAttendees}
                              onChange={(e) => setMmAttendees(e.target.value)}
                              placeholder="Alice, Bob, Carol"
                              className={inputCls}
                            />
                          </div>
                          <div>
                            <label className={labelCls}>
                              Meeting objectives{" "}
                              <span className="font-normal text-fog">(one per line)</span>
                            </label>
                            <textarea
                              value={mmObjectives}
                              onChange={(e) => setMmObjectives(e.target.value)}
                              placeholder={"Confirm weekly priorities\nReview outstanding blockers"}
                              rows={3}
                              className={`${inputCls} resize-none`}
                            />
                          </div>
                          <div>
                            <label className={labelCls}>
                              Agenda{" "}
                              <span className="font-normal text-fog">(one per line)</span>
                            </label>
                            <textarea
                              value={mmAgenda}
                              onChange={(e) => setMmAgenda(e.target.value)}
                              placeholder={"Project status updates\nFeature discussion\nNext-step alignment"}
                              rows={3}
                              className={`${inputCls} resize-none`}
                            />
                          </div>
                          <div>
                            <label className={labelCls}>Meeting notes</label>
                            <textarea
                              value={mmNotes}
                              onChange={(e) => setMmNotes(e.target.value)}
                              placeholder="Discussed sprint goals, assigned tasks..."
                              required
                              rows={5}
                              className={`${inputCls} resize-none`}
                            />
                          </div>
                          <div>
                            <label className={labelCls}>
                              Key decisions made{" "}
                              <span className="font-normal text-fog">(one per line)</span>
                            </label>
                            <textarea
                              value={mmKeyDecisions}
                              onChange={(e) => setMmKeyDecisions(e.target.value)}
                              placeholder={"Use Supabase for content storage\nKeep diary editing inside the website"}
                              rows={3}
                              className={`${inputCls} resize-none`}
                            />
                          </div>
                          <div>
                            <label className={labelCls}>
                              Action items{" "}
                              <span className="font-normal text-fog">(one per line)</span>
                            </label>
                            <textarea
                              value={mmActions}
                              onChange={(e) => setMmActions(e.target.value)}
                              placeholder={"Complete login screen\nSet up Supabase tables"}
                              rows={3}
                              className={`${inputCls} resize-none`}
                            />
                          </div>
                          <button
                            type="submit"
                            disabled={submitting}
                            className="rounded-full bg-signal-blue py-3 text-ui font-semibold text-white transition-colors hover:bg-[#0069d9] disabled:opacity-60"
                          >
                            {submitting
                              ? editingMinuteId
                                ? "Saving changes…"
                                : "Saving…"
                              : editingMinuteId
                                ? "Save changes"
                                : "Save meeting minutes"}
                          </button>
                        </motion.form>
                      ) : (
                        <motion.form
                          key="diary-form"
                          onSubmit={handleDiarySubmit}
                          initial={{ opacity: 0, x: 10 }}
                          animate={{ opacity: 1, x: 0 }}
                          exit={{ opacity: 0, x: -10 }}
                          transition={{ duration: 0.2 }}
                          className="flex flex-col gap-4"
                        >
                          <div className="rounded-xl border border-silver bg-linen px-4 py-3 text-meta leading-6 text-carbon">
                            {editingDiaryId
                              ? "You are editing an existing diary entry. Update the fields below and save your changes."
                              : "Create a new diary entry for the selected week and team member."}
                          </div>
                          <div className="grid grid-cols-2 gap-3">
                            <div>
                              <label className={labelCls}>Week label</label>
                              <input
                                value={deWeek}
                                onChange={(e) => setDeWeek(e.target.value)}
                                placeholder="e.g. Week 3"
                                required
                                className={inputCls}
                              />
                            </div>
                            <div>
                              <label className={labelCls}>Name</label>
                              <input
                                value={deName}
                                onChange={(e) => setDeName(e.target.value)}
                                placeholder="Name"
                                required
                                className={inputCls}
                              />
                            </div>
                          </div>
                          <div>
                            <label className={labelCls}>Diary Entry</label>
                            <textarea
                              value={deBody}
                              onChange={(e) => setDeBody(e.target.value)}
                              placeholder={`a) Describe the tasks you are currently working on
b) Update the completion status for each task
c) Describe any obstacles encountered that causes delay
d) Describe the work-around solution to avoid or mitigate the impact of the risks or obstacles encountered`}
                              required
                              rows={9}
                              className={`${inputCls} resize-none`}
                            />
                          </div>
                          <button
                            type="submit"
                            disabled={submitting}
                            className="rounded-full bg-signal-blue py-3 text-ui font-semibold text-white transition-colors hover:bg-[#0069d9] disabled:opacity-60"
                          >
                            {submitting
                              ? editingDiaryId
                                ? "Saving changes…"
                                : "Saving…"
                              : editingDiaryId
                                ? "Save changes"
                                : "Save diary entry"}
                          </button>
                        </motion.form>
                      )}
                    </AnimatePresence>
                  </div>
                )}
              </div>
            </motion.div>
          </>
        )}
      </AnimatePresence>

      {/* ── Toast ─────────────────────────────────────────────── */}
      <AnimatePresence>
        {toast && (
          <motion.div
            key="toast"
            className="fixed bottom-24 right-8 z-[120] flex items-center gap-2 rounded-full border border-silver bg-white px-5 py-3 text-ui font-medium text-ink shadow-whisper"
            initial={{ opacity: 0, y: 16, scale: 0.95 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 16, scale: 0.95 }}
            transition={{ duration: 0.25 }}
          >
            {toast.type === "success" ? (
              <CheckCircle2 className="h-4 w-4 text-steel" />
            ) : (
              <AlertCircle className="h-4 w-4 text-alert-red" />
            )}
            {toast.message}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
