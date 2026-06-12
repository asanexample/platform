# Minimal API controller for app-${{ values.team }}-${{ values.product }}. Exposes the liveness/readiness
# endpoint the platform manifests probe (/healthz) and a JSON root. No cloud/AWS deps — a tenant's AWS access
# (if any) is granted out-of-band via EKS Pod Identity to the named ServiceAccount.
class HealthController < ApplicationController
  APP = "app-${{ values.team }}-${{ values.product }}".freeze

  def healthz
    render json: { status: "ok" }
  end

  def index
    render json: {
      app: APP,
      version: ENV.fetch("VERSION", "dev"),
      namespace: ENV.fetch("NAMESPACE", "unknown"),
      hostname: request.host_with_port,
      timestamp: Time.now.utc.iso8601
    }
  end
end
