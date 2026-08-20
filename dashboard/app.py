import asyncio
import hashlib
import json
import os
import secrets
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from aiohttp import ClientSession, ClientTimeout, WSMsgType, web

HA_URL = os.getenv("HA_URL", "http://127.0.0.1:8123").rstrip("/")
HA_TOKEN = os.getenv("HA_TOKEN", "")
HA_VERIFY_TLS = os.getenv("HA_VERIFY_TLS", "1").strip().lower() not in {
    "0",
    "false",
    "no",
    "off",
}
VACUUM_ENTITY = os.getenv("VACUUM_ENTITY", "").strip()
MAP_ENTITY = os.getenv("MAP_ENTITY", "").strip()
HOST = os.getenv("DASHBOARD_HOST", "0.0.0.0")
PORT = int(os.getenv("DASHBOARD_PORT", "8090"))
ARCHIVE_DIR = Path(os.getenv("ARCHIVE_DIR", "/data/maps"))
ARCHIVE_INTERVAL = int(os.getenv("ARCHIVE_INTERVAL", "180"))
ARCHIVE_KEEP = int(os.getenv("ARCHIVE_KEEP", "80"))
TIMEOUT = ClientTimeout(total=15)


def headers() -> dict[str, str]:
    return {
        "Authorization": f"Bearer {HA_TOKEN}",
        "Content-Type": "application/json",
    }


async def ha_json(method: str, path: str, payload: Any | None = None) -> Any:
    async with ClientSession(timeout=TIMEOUT) as session:
        async with session.request(
            method,
            HA_URL + path,
            headers=headers(),
            json=payload,
            ssl=None if HA_VERIFY_TLS else False,
        ) as resp:
            text = await resp.text()
            if resp.status >= 400:
                raise web.HTTPBadGateway(
                    text=f"Home Assistant {resp.status}: {text[:500]}"
                )
            return json.loads(text) if text else None


async def discover(app: web.Application, force: bool = False) -> dict[str, str | None]:
    ent = app["entities"]
    if not force and ent.get("vacuum") and ent.get("map"):
        return ent

    states = await ha_json("GET", "/api/states")
    if not ent.get("vacuum"):
        vacs = [s for s in states if s.get("entity_id", "").startswith("vacuum.")]
        if vacs:
            preferred = [
                s
                for s in vacs
                if any(
                    marker
                    in (
                        s.get("attributes", {}).get("friendly_name", "")
                        + s.get("entity_id", "")
                    ).lower()
                    for marker in ("deebot", "ecovacs", "x1")
                )
            ]
            ent["vacuum"] = (preferred or vacs)[0]["entity_id"]

    if not ent.get("map"):
        images = [s for s in states if s.get("entity_id", "").startswith("image.")]
        maps = [
            s
            for s in images
            if "map"
            in (
                s.get("attributes", {}).get("friendly_name", "")
                + s.get("entity_id", "")
            ).lower()
            or "карт"
            in (
                s.get("attributes", {}).get("friendly_name", "")
                + s.get("entity_id", "")
            ).lower()
        ]
        if maps:
            preferred = [
                s
                for s in maps
                if any(
                    marker
                    in (
                        s.get("attributes", {}).get("friendly_name", "")
                        + s.get("entity_id", "")
                    ).lower()
                    for marker in ("deebot", "ecovacs", "x1")
                )
            ]
            ent["map"] = (preferred or maps)[0]["entity_id"]

    return ent


def require_csrf(request: web.Request) -> None:
    supplied = request.headers.get("X-DEEBOT-CSRF", "")
    expected = request.app["csrf_token"]
    if not supplied or not secrets.compare_digest(supplied, expected):
        raise web.HTTPForbidden(text="invalid CSRF token")


def validate_requested_areas(
    requested: Any, available: list[dict[str, str]]
) -> list[str]:
    if not isinstance(requested, list) or not requested or len(requested) > 32:
        raise web.HTTPBadRequest(text="1..32 cleaning areas are required")
    if any(not isinstance(area_id, str) or not area_id for area_id in requested):
        raise web.HTTPBadRequest(text="invalid area id")

    allowed = {item["id"] for item in available}
    unique = list(dict.fromkeys(requested))
    unknown = [area_id for area_id in unique if area_id not in allowed]
    if unknown:
        raise web.HTTPBadRequest(text="area is not mapped to this vacuum")
    return unique


async def api_session(request: web.Request) -> web.Response:
    return web.json_response({"csrf": request.app["csrf_token"]})


async def api_status(request: web.Request) -> web.Response:
    if not HA_TOKEN:
        return web.json_response(
            {"ok": False, "error": "HA_TOKEN is not configured"}, status=503
        )
    ent = await discover(request.app)
    if not ent.get("vacuum"):
        return web.json_response(
            {"ok": False, "error": "vacuum entity not found", "entities": ent},
            status=404,
        )
    state = await ha_json("GET", f"/api/states/{ent['vacuum']}")
    attrs = state.get("attributes", {})
    return web.json_response(
        {
            "ok": True,
            "entity": ent["vacuum"],
            "map_entity": ent.get("map"),
            "name": attrs.get("friendly_name", "DEEBOT X1"),
            "state": state.get("state"),
            "battery": attrs.get("battery_level"),
            "fan_speed": attrs.get("fan_speed"),
            "attributes": {
                key: attrs.get(key)
                for key in ("status", "error", "cleaned_area", "cleaning_time")
                if key in attrs
            },
        }
    )


async def api_action(request: web.Request) -> web.Response:
    require_csrf(request)
    ent = await discover(request.app)
    vacuum = ent.get("vacuum")
    if not vacuum:
        raise web.HTTPNotFound(text="vacuum entity not found")

    action = request.match_info["action"]
    services = {
        "start": "start",
        "pause": "pause",
        "stop": "stop",
        "home": "return_to_base",
        "locate": "locate",
    }
    if action not in services:
        raise web.HTTPBadRequest(text="unsupported action")
    result = await ha_json(
        "POST", f"/api/services/vacuum/{services[action]}", {"entity_id": vacuum}
    )
    return web.json_response({"ok": True, "result": result})


async def ws_areas(app: web.Application) -> list[dict[str, str]]:
    """Return only HA Areas mapped to this vacuum's cleanable segments."""
    ent = await discover(app)
    vacuum = ent.get("vacuum")
    if not vacuum:
        return []

    ws_url = (
        HA_URL.replace("https://", "wss://").replace("http://", "ws://")
        + "/api/websocket"
    )
    async with ClientSession(timeout=TIMEOUT) as session:
        async with session.ws_connect(
            ws_url, heartbeat=20, ssl=None if HA_VERIFY_TLS else False
        ) as ws:
            first = await ws.receive_json()
            if first.get("type") != "auth_required":
                raise RuntimeError("unexpected websocket greeting")
            await ws.send_json({"type": "auth", "access_token": HA_TOKEN})
            auth = await ws.receive_json()
            if auth.get("type") != "auth_ok":
                raise RuntimeError("Home Assistant websocket authentication failed")

            await ws.send_json(
                {"id": 1, "type": "config/entity_registry/get", "entity_id": vacuum}
            )
            entry = None
            while True:
                msg = await ws.receive()
                if msg.type != WSMsgType.TEXT:
                    raise RuntimeError("websocket closed")
                data = json.loads(msg.data)
                if data.get("id") == 1:
                    if not data.get("success"):
                        raise RuntimeError(str(data))
                    entry = data.get("result") or {}
                    break

            options = (entry or {}).get("options") or {}
            mapping = ((options.get("vacuum") or {}).get("area_mapping") or {})
            mapped_area_ids = set(mapping.keys())
            if not mapped_area_ids:
                return []

            await ws.send_json({"id": 2, "type": "config/area_registry/list"})
            while True:
                msg = await ws.receive()
                if msg.type != WSMsgType.TEXT:
                    raise RuntimeError("websocket closed")
                data = json.loads(msg.data)
                if data.get("id") == 2:
                    if not data.get("success"):
                        raise RuntimeError(str(data))
                    areas = data.get("result", [])
                    return [
                        {"id": item["area_id"], "name": item.get("name") or item["area_id"]}
                        for item in areas
                        if item.get("area_id") in mapped_area_ids
                    ]


async def api_areas(request: web.Request) -> web.Response:
    try:
        return web.json_response({"ok": True, "areas": await ws_areas(request.app)})
    except Exception as exc:  # noqa: BLE001 - HTTP boundary returns diagnostic text
        return web.json_response(
            {"ok": False, "error": str(exc), "areas": []}, status=502
        )


async def api_clean_areas(request: web.Request) -> web.Response:
    require_csrf(request)
    ent = await discover(request.app)
    vacuum = ent.get("vacuum")
    if not vacuum:
        raise web.HTTPNotFound(text="vacuum entity not found")

    try:
        body = await request.json()
    except (json.JSONDecodeError, ValueError) as exc:
        raise web.HTTPBadRequest(text="invalid JSON") from exc

    areas = validate_requested_areas(body.get("areas"), await ws_areas(request.app))
    payload = {"entity_id": vacuum, "cleaning_area_id": areas}
    result = await ha_json("POST", "/api/services/vacuum/clean_area", payload)
    return web.json_response({"ok": True, "result": result})


async def get_map_bytes(app: web.Application) -> tuple[bytes, str]:
    ent = await discover(app)
    map_entity = ent.get("map")
    if not map_entity:
        raise web.HTTPNotFound(text="map image entity not found")
    async with ClientSession(timeout=TIMEOUT) as session:
        async with session.get(
            HA_URL + f"/api/image_proxy/{map_entity}",
            headers=headers(),
            ssl=None if HA_VERIFY_TLS else False,
        ) as resp:
            if resp.status >= 400:
                raise web.HTTPBadGateway(
                    text=f"Home Assistant map proxy returned {resp.status}"
                )
            return await resp.read(), resp.headers.get(
                "content-type", "image/svg+xml"
            )


async def api_map(request: web.Request) -> web.Response:
    content, content_type = await get_map_bytes(request.app)
    return web.Response(body=content, content_type=content_type.split(";")[0])


async def archive_once(app: web.Application) -> None:
    try:
        content, content_type = await get_map_bytes(app)
        if not content:
            return
        ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)
        digest = hashlib.sha256(content).hexdigest()
        last = ARCHIVE_DIR / ".last-sha256"
        if last.exists() and last.read_text().strip() == digest:
            return
        extension = ".svg" if "svg" in content_type else ".png"
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        path = ARCHIVE_DIR / f"map-{stamp}-{digest[:10]}{extension}"
        path.write_bytes(content)
        last.write_text(digest)
        maps = sorted(
            [item for item in ARCHIVE_DIR.iterdir() if item.name.startswith("map-")],
            key=lambda item: item.stat().st_mtime,
            reverse=True,
        )
        for old in maps[ARCHIVE_KEEP:]:
            old.unlink(missing_ok=True)
    except Exception as exc:  # noqa: BLE001 - background archival must not stop UI
        print(f"map archive skipped: {exc}", flush=True)


async def archive_loop(app: web.Application) -> None:
    while True:
        await archive_once(app)
        await asyncio.sleep(max(30, ARCHIVE_INTERVAL))


async def on_startup(app: web.Application) -> None:
    ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)
    app["archive_task"] = asyncio.create_task(archive_loop(app))


async def on_cleanup(app: web.Application) -> None:
    task = app.get("archive_task")
    if task:
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass


async def add_security_headers(
    request: web.Request, response: web.StreamResponse
) -> None:
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; img-src 'self' data:; style-src 'self'; "
        "script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'"
    )
    if request.path.startswith("/api/"):
        response.headers["Cache-Control"] = "no-store"


def create_app() -> web.Application:
    app = web.Application(client_max_size=32 * 1024)
    app["entities"] = {"vacuum": VACUUM_ENTITY or None, "map": MAP_ENTITY or None}
    app["csrf_token"] = secrets.token_urlsafe(32)

    static = Path(__file__).parent / "static"
    app.router.add_get("/api/session", api_session)
    app.router.add_get("/api/status", api_status)
    app.router.add_post("/api/action/{action}", api_action)
    app.router.add_get("/api/areas", api_areas)
    app.router.add_post("/api/clean-areas", api_clean_areas)
    app.router.add_get("/api/map", api_map)
    app.router.add_static("/static/", static, show_index=False)
    app.router.add_get("/", lambda request: web.FileResponse(static / "index.html"))
    app.router.add_get(
        "/manifest.webmanifest",
        lambda request: web.FileResponse(static / "manifest.webmanifest"),
    )
    app.router.add_get("/sw.js", lambda request: web.FileResponse(static / "sw.js"))
    app.on_startup.append(on_startup)
    app.on_cleanup.append(on_cleanup)
    app.on_response_prepare.append(add_security_headers)
    return app


if __name__ == "__main__":
    web.run_app(create_app(), host=HOST, port=PORT)
