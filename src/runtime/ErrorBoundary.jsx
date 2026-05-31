import React from "react";

export default class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(error) {
    return { error };
  }

  componentDidCatch(error, info) {
    console.error("Pax Historia render failure", error, info);
  }

  render() {
    if (!this.state.error) {
      return this.props.children;
    }

    return (
      <div className="fatal-shell">
        <div className="fatal-panel">
          <div className="fatal-eyebrow">Runtime recovered</div>
          <h1>Pax Historia hit a bad state.</h1>
          <p>
            The map was protected from a full crash. Reload the campaign, or reset the current
            browser state if this repeats after an AI-generated turn.
          </p>
          <pre>{this.state.error?.message || "Unknown error"}</pre>
          <button onClick={() => window.location.reload()}>Reload campaign</button>
        </div>
      </div>
    );
  }
}
