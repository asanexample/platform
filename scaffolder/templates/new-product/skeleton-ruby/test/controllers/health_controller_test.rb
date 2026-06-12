require "test_helper"

# Asserts the liveness/readiness endpoint the platform probes returns 200 {"status":"ok"}.
class HealthControllerTest < ActionDispatch::IntegrationTest
  test "GET /healthz returns 200 ok" do
    get "/healthz"
    assert_response :success
    assert_equal "ok", JSON.parse(response.body)["status"]
  end
end
