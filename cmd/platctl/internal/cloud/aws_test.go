package cloud

import "testing"

func TestRegionFromAuth_Default(t *testing.T) {
	auth := map[string]string{"profile": "management"}
	if r := RegionFromAuth(auth); r != "us-east-1" {
		t.Fatalf("expected us-east-1, got %q", r)
	}
}

func TestRegionFromAuth_Explicit(t *testing.T) {
	auth := map[string]string{"profile": "management", "region": "eu-west-1"}
	if r := RegionFromAuth(auth); r != "eu-west-1" {
		t.Fatalf("expected eu-west-1, got %q", r)
	}
}

func TestRegionFromAuth_Empty(t *testing.T) {
	auth := map[string]string{"region": ""}
	if r := RegionFromAuth(auth); r != "us-east-1" {
		t.Fatalf("expected us-east-1 for empty region, got %q", r)
	}
}

func TestRegionFromAuth_NilMap(t *testing.T) {
	if r := RegionFromAuth(nil); r != "us-east-1" {
		t.Fatalf("expected us-east-1 for nil auth, got %q", r)
	}
}
