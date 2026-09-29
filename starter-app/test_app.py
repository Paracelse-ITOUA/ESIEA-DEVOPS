from app import alert_threshold, sanitize_input, app


def test_alert_threshold():
    assert alert_threshold() == 25


def test_sanitize_input_escapes_html():
    assert sanitize_input("<script>") == "&lt;script&gt;"


def test_health_endpoint():
    client = app.test_client()
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json()["status"] == "ok"


def test_status_endpoint():
    client = app.test_client()
    response = client.get("/status")

    assert response.status_code == 200
    assert response.get_json()["service"] == "projet-devops-groupe-demo"
    assert response.get_json()["version"] == "1.1"
