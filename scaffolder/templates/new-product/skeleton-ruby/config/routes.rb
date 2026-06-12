Rails.application.routes.draw do
  # The liveness/readiness endpoint the platform manifests probe.
  get "healthz", to: "health#healthz"
  # JSON root.
  root "health#index"
end
