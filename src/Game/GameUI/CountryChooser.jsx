import React from "react";
import { createPortal } from "react-dom";
import { loadCountryNames } from "../../runtime/assets.js";
import { getFallbackCountries } from "../../runtime/countryFallbacks.js";
import { selectPlayerCountry } from "../../runtime/playerCountry.js";

const overlayStyle = {
  alignItems: "center",
  background: "rgba(2, 6, 23, 0.62)",
  display: "flex",
  inset: 0,
  justifyContent: "center",
  padding: "max(1rem, env(safe-area-inset-top)) max(1rem, env(safe-area-inset-right)) max(1rem, env(safe-area-inset-bottom)) max(1rem, env(safe-area-inset-left))",
  position: "fixed",
  zIndex: 10080,
};

const panelStyle = {
  background: "linear-gradient(180deg, rgba(15, 23, 42, 0.98), rgba(8, 13, 24, 0.98))",
  border: "1px solid rgba(255,255,255,0.11)",
  borderRadius: "12px",
  boxShadow: "0 24px 70px rgba(0,0,0,0.48)",
  color: "white",
  display: "flex",
  flexDirection: "column",
  fontFamily: "sans-serif",
  maxHeight: "min(42rem, calc(100vh - 2rem))",
  overflow: "hidden",
  width: "min(38rem, calc(100vw - 2rem))",
};

const buttonStyle = {
  background: "rgba(255,255,255,0.06)",
  border: "1px solid rgba(255,255,255,0.09)",
  borderRadius: "8px",
  color: "rgba(255,255,255,0.9)",
  cursor: "pointer",
  font: "inherit",
  padding: "0.7rem 0.8rem",
  textAlign: "left",
};

const mergeCountries = (primary, fallback) => {
  const seen = new Map();
  for (const country of [...(primary ?? []), ...(fallback ?? [])]) {
    const name = String(country?.name ?? "").trim();
    if (!name) continue;
    const key = name.toLowerCase();
    if (!seen.has(key)) {
      seen.set(key, {
        code: String(country?.code ?? "").trim(),
        name,
      });
    }
  }

  return Array.from(seen.values()).sort((left, right) => left.name.localeCompare(right.name));
};

const CountryChooser = ({ isOpen, onClose }) => {
  const [countries, setCountries] = React.useState([]);
  const [error, setError] = React.useState("");
  const [isLoading, setIsLoading] = React.useState(false);
  const [query, setQuery] = React.useState("");
  const [savingCode, setSavingCode] = React.useState("");

  React.useEffect(() => {
    if (!isOpen) return;

    let cancelled = false;
    setIsLoading(true);
    setError("");

    loadCountryNames({ force: true })
      .catch((loadError) => {
        setError(loadError instanceof Error ? loadError.message : "Map country data did not load.");
        return [];
      })
      .then((loadedCountries) => {
        if (cancelled) return;
        setCountries(mergeCountries(loadedCountries, getFallbackCountries(navigator.language)));
      })
      .finally(() => {
        if (!cancelled) setIsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [isOpen]);

  React.useEffect(() => {
    if (!isOpen) return undefined;
    const onKeyDown = (event) => {
      if (event.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  const normalizedQuery = query.trim().toLowerCase();
  const filteredCountries = countries
    .filter((country) => {
      if (!normalizedQuery) return true;
      return (
        country.name.toLowerCase().includes(normalizedQuery) ||
        country.code.toLowerCase().includes(normalizedQuery)
      );
    })
    .slice(0, 80);

  const handleChoose = async (country) => {
    setSavingCode(country.code || country.name);
    setError("");

    try {
      await selectPlayerCountry(country);
      onClose();
    } catch (chooseError) {
      setError(chooseError instanceof Error ? chooseError.message : "Could not choose this country.");
    } finally {
      setSavingCode("");
    }
  };

  return createPortal(
    <div data-testid="country-chooser" style={overlayStyle}>
      <div style={panelStyle}>
        <div style={{ alignItems: "center", display: "flex", gap: "1rem", padding: "1rem 1rem 0.85rem" }}>
          <div style={{ minWidth: 0 }}>
            <div style={{ fontSize: "1.05rem", fontWeight: 800 }}>Choose Player Country</div>
            <div style={{ color: "rgba(255,255,255,0.55)", fontSize: "0.8rem", marginTop: "0.18rem" }}>
              This changes who you play as without resetting the campaign.
            </div>
          </div>
          <button
            onClick={onClose}
            style={{ ...buttonStyle, marginLeft: "auto", padding: "0.45rem 0.65rem" }}
            type="button"
          >
            Close
          </button>
        </div>

        <div style={{ padding: "0 1rem 0.8rem" }}>
          <input
            autoFocus
            data-testid="country-chooser-search"
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search country or ISO code..."
            style={{
              background: "rgba(255,255,255,0.08)",
              border: "1px solid rgba(255,255,255,0.12)",
              borderRadius: "8px",
              color: "white",
              font: "inherit",
              outline: "none",
              padding: "0.78rem 0.9rem",
              width: "100%",
            }}
            value={query}
          />
          {error && (
            <div style={{ color: "#fecaca", fontSize: "0.78rem", marginTop: "0.55rem" }}>
              {error}
            </div>
          )}
        </div>

        <div
          style={{
            display: "grid",
            gap: "0.45rem",
            gridTemplateColumns: "repeat(auto-fill, minmax(10rem, 1fr))",
            overflow: "auto",
            padding: "0 1rem 1rem",
          }}
        >
          {isLoading && <div style={{ color: "rgba(255,255,255,0.6)" }}>Loading countries...</div>}
          {!isLoading && filteredCountries.map((country) => {
            const isSaving = savingCode === (country.code || country.name);
            return (
              <button
                data-testid="country-chooser-option"
                disabled={Boolean(savingCode)}
                key={`${country.code}-${country.name}`}
                onClick={() => handleChoose(country)}
                style={{
                  ...buttonStyle,
                  opacity: savingCode && !isSaving ? 0.55 : 1,
                }}
                type="button"
              >
                <span style={{ display: "block", fontWeight: 750, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                  {isSaving ? "Choosing..." : country.name}
                </span>
                {country.code && (
                  <span style={{ color: "rgba(255,255,255,0.45)", display: "block", fontSize: "0.72rem", marginTop: "0.18rem" }}>
                    {country.code}
                  </span>
                )}
              </button>
            );
          })}
          {!isLoading && filteredCountries.length === 0 && (
            <div style={{ color: "rgba(255,255,255,0.62)", gridColumn: "1 / -1" }}>
              No country matched that search.
            </div>
          )}
        </div>
      </div>
    </div>,
    document.body,
  );
};

export default CountryChooser;
