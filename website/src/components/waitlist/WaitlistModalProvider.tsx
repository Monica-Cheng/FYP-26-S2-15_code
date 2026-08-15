"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type FormEvent,
  type ReactNode,
} from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Loader2, X } from "lucide-react";
import { siteConfig } from "@/content/site-config";

type Status = "idle" | "loading" | "success" | "duplicate" | "error";

type WaitlistModalContextValue = {
  openModal: () => void;
  closeModal: () => void;
};

const WaitlistModalContext = createContext<WaitlistModalContextValue | null>(null);

export function useWaitlistModal() {
  const context = useContext(WaitlistModalContext);

  if (!context) {
    throw new Error("useWaitlistModal must be used within WaitlistModalProvider");
  }

  return context;
}

export default function WaitlistModalProvider({
  children,
}: {
  children: ReactNode;
}) {
  const [isOpen, setIsOpen] = useState(false);
  const [email, setEmail] = useState("");
  const [status, setStatus] = useState<Status>("idle");
  const inputRef = useRef<HTMLInputElement>(null);
  const copy = siteConfig.waitlist;

  const closeModal = useCallback(() => {
    setIsOpen(false);
  }, []);

  const openModal = useCallback(() => {
    setIsOpen(true);
  }, []);

  useEffect(() => {
    if (!isOpen) {
      document.body.style.overflow = "";
      return;
    }

    document.body.style.overflow = "hidden";
    const timer = window.setTimeout(() => inputRef.current?.focus(), 120);

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape" && status !== "loading") {
        closeModal();
      }
    };

    window.addEventListener("keydown", onKeyDown);

    return () => {
      window.clearTimeout(timer);
      window.removeEventListener("keydown", onKeyDown);
      document.body.style.overflow = "";
    };
  }, [closeModal, isOpen, status]);

  useEffect(() => {
    if (!isOpen) {
      const timer = window.setTimeout(() => {
        setStatus("idle");
        setEmail("");
      }, 180);

      return () => window.clearTimeout(timer);
    }
  }, [isOpen]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setStatus("loading");

    try {
      const response = await fetch("/api/waitlist", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email }),
      });

      if (response.ok) {
        setStatus("success");
        setEmail("");
        return;
      }

      if (response.status === 409) {
        setStatus("duplicate");
        return;
      }

      setStatus("error");
    } catch {
      setStatus("error");
    }
  }

  const contextValue = useMemo(
    () => ({
      openModal,
      closeModal,
    }),
    [closeModal, openModal],
  );

  return (
    <WaitlistModalContext.Provider value={contextValue}>
      {children}

      <AnimatePresence>
        {isOpen ? (
          <motion.div
            className="fixed inset-0 z-[100] flex items-center justify-center px-4 py-6"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
          >
            <motion.button
              type="button"
              aria-label="Close waitlist modal"
              className="absolute inset-0 bg-deep-indigo/60"
              onClick={() => {
                if (status !== "loading") closeModal();
              }}
            />

            <motion.div
              role="dialog"
              aria-modal="true"
              aria-labelledby="waitlist-heading"
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: 8 }}
              transition={{ duration: 0.2, ease: "easeOut" }}
              className="relative z-10 w-full max-w-lg rounded-float border border-silver bg-white p-7 shadow-whisper md:p-8"
            >
              <div className="flex items-start justify-between gap-4">
                <h2
                  id="waitlist-heading"
                  className="text-heading font-bold text-ink"
                >
                  {copy.heading}
                </h2>

                <button
                  type="button"
                  onClick={closeModal}
                  disabled={status === "loading"}
                  className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-ink/50 text-ink transition-colors hover:bg-ink/[0.04] disabled:cursor-not-allowed disabled:opacity-60"
                  aria-label="Close modal"
                >
                  <X className="h-4 w-4" />
                </button>
              </div>

              <p className="mt-3 text-lede text-carbon">{copy.lede}</p>

              <div className="mt-7">
                {status === "success" ? (
                  <div className="rounded-card border border-silver bg-linen px-5 py-5">
                    <p className="text-heading-sm font-semibold text-ink">
                      {copy.successTitle}
                    </p>
                    <p className="mt-2 text-lede text-carbon">{copy.successBody}</p>
                  </div>
                ) : (
                  <form onSubmit={handleSubmit} className="space-y-4">
                    <label className="block">
                      <span className="mb-2 block text-meta font-medium text-carbon">
                        {copy.inputLabel}
                      </span>
                      <input
                        ref={inputRef}
                        type="email"
                        value={email}
                        onChange={(event) => setEmail(event.target.value)}
                        placeholder={copy.placeholder}
                        required
                        className="w-full rounded-xl border border-silver bg-white px-4 py-3 text-ui text-ink outline-none transition-colors placeholder:text-fog focus:border-signal-blue"
                      />
                    </label>

                    {/* The one filled #007bff button on this surface */}
                    <button
                      type="submit"
                      disabled={status === "loading"}
                      className="inline-flex w-full items-center justify-center gap-2 rounded-full bg-signal-blue px-6 py-3 text-ui font-semibold text-white transition-colors hover:bg-[#0069d9] disabled:cursor-not-allowed disabled:opacity-60"
                    >
                      {status === "loading" ? (
                        <>
                          <Loader2 className="h-4 w-4 animate-spin" />
                          {copy.submitting}
                        </>
                      ) : (
                        copy.submit
                      )}
                    </button>

                    <p className="text-meta text-steel">{copy.riskReversal}</p>
                  </form>
                )}

                {status === "duplicate" ? (
                  <p className="mt-4 text-meta text-carbon">{copy.duplicate}</p>
                ) : null}

                {status === "error" ? (
                  <p className="mt-4 text-meta text-alert-red">{copy.error}</p>
                ) : null}
              </div>
            </motion.div>
          </motion.div>
        ) : null}
      </AnimatePresence>
    </WaitlistModalContext.Provider>
  );
}
