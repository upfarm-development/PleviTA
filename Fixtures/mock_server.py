#!/usr/bin/env python3
"""Local mock of a Tube Archivist server, for Plevi TA development only.

Standard library only (`http.server`). Serves canned, synthetic JSON that matches Tube Archivist's response shapes
for login and ping, user and account, a paginated and filterable video list, video detail and playback media,
channels, playlists and search, so the app can be exercised without a real server.
"""

from __future__ import annotations

import hashlib
import json
import secrets
import struct
import sys
import threading
import zlib
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

# --- Synthetic, local-only mock account. Not a real credential. ------------
MOCK_USERNAME = "admin"
MOCK_PASSWORD = "admin123"

MOCK_TOKEN = "synthetic0fixture0token0000000000000000"

MOCK_VERSION = "v0.5.12-mock"

MEDIA_DIR = Path(__file__).resolve().parent / "media"

_SUBTITLE_VTT_BYTES = (
    "WEBVTT\n\n"
    "00:00:00.000 --> 00:00:05.000\nSynthetic subtitle track — Fixtures/mock_server.py.\n\n"
    "00:00:05.000 --> 00:00:10.000\nNot real captions; exercises the subtitle menu.\n\n"
    "00:01:00.000 --> 00:01:05.000\nStill playing at the one-minute mark.\n"
).encode("utf-8")

# GET/POST /api/user/me/ per-user config.
DEFAULT_USER_CONFIG = {
    "page_size": 12,
    "sort_by": "published",
    "sort_order": "desc",
    "hide_watched": False,
    "hide_watched_channel": False,
    "hide_watched_playlist": False,
    "vid_type_filter": "videos",
    "show_subed_only": True,
    "show_subed_only_playlists": False,
    "grid_items": 3,
    "view_style_home": "grid",
    "view_style_channel": "grid",
    "view_style_playlist": "grid",
    "view_style_downloads": "list",
    "stylesheet": "dark.css",
    "file_size_unit": "binary",
    "show_ignored_only": False,
    "show_help_text": True,
}

CHANNELS: list[dict] = [
    {
        "channel_id": "channel_alpha01",
        "channel_name": "Alpha Aerials",
        "channel_thumb_url": "/cache/channels/channel_alpha01/thumb.jpg",
        "channel_banner_url": "/cache/channels/channel_alpha01/banner.jpg",
        "channel_tvart_url": "/cache/channels/channel_alpha01/tvart.jpg",
        "channel_subscribed": True,
        "channel_description": "Synthetic mock channel: drone flights and travel vlogs.",
        "channel_last_refresh": "2026-09-01",
        "channel_subs": 128_400,
        "channel_views": 9_812_300,
    },
    {
        "channel_id": "channel_beta002",
        "channel_name": "Beta Bytes",
        "channel_thumb_url": "/cache/channels/channel_beta002/thumb.jpg",
        "channel_banner_url": "/cache/channels/channel_beta002/banner.jpg",
        "channel_tvart_url": "/cache/channels/channel_beta002/tvart.jpg",
        "channel_subscribed": False,
        "channel_description": "Synthetic mock channel: programming tutorials.",
        "channel_last_refresh": "2026-08-28",
        "channel_subs": 54_900,
        "channel_views": 3_204_100,
    },
    {
        "channel_id": "channel_gamma03",
        "channel_name": "Gamma Grill Home Cooking & Recipe Archive",
        "channel_thumb_url": "/cache/channels/channel_gamma03/thumb.jpg",
        "channel_banner_url": "/cache/channels/channel_gamma03/banner.jpg",
        "channel_tvart_url": "/cache/channels/channel_gamma03/tvart.jpg",
        "channel_subscribed": True,
        "channel_description": "Synthetic mock channel: home cooking demos.",
        "channel_last_refresh": "2026-09-05",
        "channel_subs": 210_700,
        "channel_views": 15_667_800,
    },
]

_UNCACHED_CHANNEL_ART_PATHS = {
    "/cache/channels/channel_beta002/banner.jpg",
    "/cache/channels/channel_beta002/tvart.jpg",
}

CHANNEL_PAGE_SIZE = 2

_TOPICS = [
    "Getting Started", "Deep Dive", "Live Q&A", "Behind the Scenes",
    "Weekly Update", "Full Tutorial", "Highlights Reel", "Studio Interview",
    "Quick Tips", "Season Finale", "Community Spotlight", "First Look",
]

VIDEO_COUNT = 32
VIDEO_PAGE_SIZE = 12
FALLBACK_TEST_VIDEO_ID = f"video{VIDEO_COUNT:03d}mock"
# First N videos watched, next M in-progress ("continue watching"), the rest
# untouched — picked so all three states, plus pagination (32 / 12 = 3
# pages) and every sort/type filter, have several matching videos to show.
_WATCHED_COUNT = 6
_CONTINUE_COUNT = 5


def _format_published(ts: float) -> str:
    # The app must parse this (PleviFormatting.displayDate) and show a date only, never this raw string.
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00")


def _format_duration(total_seconds: float) -> str:
    total = int(total_seconds)
    hours, remainder = divmod(total, 3600)
    minutes, seconds = divmod(remainder, 60)
    if hours:
        return f"{hours}:{minutes:02d}:{seconds:02d}"
    return f"{minutes}:{seconds:02d}"


def _sponsorblock_for(index: int, duration: float) -> dict | None:
    state = index % 3
    if state == 0:
        return None
    if state == 1:
        return {"is_enabled": True, "last_refresh": 1_789_718_378, "segments": []}
    selfpromo = (round(duration * 0.15, 1), round(duration * 0.18, 1))
    outro = (round(duration * 0.97, 1), duration)
    # poi_highlight segments are zero-length on the wire (confirmed live) — start == end.
    poi = round(duration * 0.55, 1)
    return {
        "is_enabled": True,
        "last_refresh": 1_789_466_431,
        "has_unlocked": True,
        "segments": [
            {
                "actionType": "none", "videoDuration": duration, "segment": list(selfpromo),
                "votes": 0, "category": "selfpromo", "UUID": f"mockselfpromo{index:03d}", "locked": 0,
            },
            {
                "actionType": "none", "videoDuration": duration, "segment": list(outro),
                "votes": 1, "category": "outro", "UUID": f"mockoutro{index:03d}", "locked": 0,
            },
            {
                "actionType": "none", "videoDuration": duration, "segment": [poi, poi],
                "votes": 0, "category": "poi_highlight", "UUID": f"mockpoi{index:03d}", "locked": 0,
            },
        ],
    }


def _build_videos() -> tuple[list[dict], dict[str, dict]]:
    videos: list[dict] = []
    sort_keys: dict[str, dict] = {}
    now = 1_757_000_000.0  # fixed reference instant, for deterministic output

    for i in range(VIDEO_COUNT):
        channel = CHANNELS[i % len(CHANNELS)]
        topic = _TOPICS[i % len(_TOPICS)]
        youtube_id = f"video{i + 1:03d}mock"

        if i % 11 == 10:
            vid_type = "streams"
        elif i % 8 == 7:
            vid_type = "shorts"
        else:
            vid_type = "videos"

        duration = 180 + (i * 137) % 1800  # ~3-33 synthetic minutes
        downloaded_ts = now - i * 86_400  # each one day "older" than the last
        published_ts = downloaded_ts - 3600 * ((i % 5) + 1)

        is_watched = i < _WATCHED_COUNT
        is_continuing = _WATCHED_COUNT <= i < _WATCHED_COUNT + _CONTINUE_COUNT
        position = round(duration * 0.4, 1) if is_continuing else None
        progress = 40.0 if is_continuing else None

        view_count = 100 + i * 17
        like_count = 10 + i * 2
        media_size = 40_000_000 + i * 654_321

        video = {
            "youtube_id": youtube_id,
            "title": f"{channel['channel_name']}: {topic} #{i + 1}",
            "description": (
                f"Synthetic mock description for the \"{topic}\" episode of "
                f"{channel['channel_name']}. Not real content — generated by "
                "Fixtures/mock_server.py for local development."
            ),
            "published": _format_published(published_ts),
            "date_downloaded": downloaded_ts,
            "vid_type": vid_type,
            "vid_thumb_url": f"/cache/videos/{channel['channel_id']}/{youtube_id}.jpg",
            "media_url": f"/media/{channel['channel_id']}/{youtube_id}.mp4",
            "media_size": media_size,
            "active": True,
            "tags": [],
            "category": [],
            "comment_count": 0,
            "streams": [
                {"type": "video", "codec": "h264", "width": 1920, "height": 1080, "bitrate": 5_000_000},
                {"type": "audio", "codec": "aac", "width": None, "height": None, "bitrate": 128_000},
            ],
            "stats": {
                "view_count": view_count,
                "like_count": like_count,
                "dislike_count": 0,
                "average_rating": 4.2,
            },
            "player": {
                "duration": duration,
                "duration_str": _format_duration(duration),
                "watched": is_watched,
                "position": position,
                "progress": progress,
            },
            "channel": dict(channel),
            "subtitles": [],
            "playlist": [],
        }
        sponsorblock = _sponsorblock_for(i, duration)
        if sponsorblock is not None:
            video["sponsorblock"] = sponsorblock
        videos.append(video)
        sort_keys[youtube_id] = {
            "published": published_ts,
            "downloaded": downloaded_ts,
            "views": view_count,
            "likes": like_count,
            "duration": duration,
            "filesize": media_size,
        }

    for vid_id in ("video012mock", "video013mock", "video014mock"):
        video = next(v for v in videos if v["youtube_id"] == vid_id)
        video["player"]["duration"] = 90.0
        video["player"]["duration_str"] = _format_duration(90.0)
        sort_keys[vid_id]["duration"] = 90.0

    av1_video = next(v for v in videos if v["youtube_id"] == FALLBACK_TEST_VIDEO_ID)
    av1_video["streams"] = [
        {"type": "video", "codec": "av1", "width": 960, "height": 540, "bitrate": 1_200_000},
        {"type": "audio", "codec": "opus", "width": None, "height": None, "bitrate": 96_000},
    ]
    av1_video["media_size"] = 14_600_000  # matches Fixtures/media/sample_av1_opus.mp4 on disk
    av1_video["player"]["duration"] = 90.0
    av1_video["player"]["duration_str"] = _format_duration(90.0)
    av1_video["subtitles"] = [
        {
            "name": "English (auto)",
            "lang": "en",
            "media_url": f"/media/{av1_video['channel']['channel_id']}/{FALLBACK_TEST_VIDEO_ID}.en.vtt",
            "source": "auto",
        }
    ]
    sort_keys[FALLBACK_TEST_VIDEO_ID]["duration"] = 90.0

    short_title_video = next(v for v in videos if v["youtube_id"] == "video007mock")
    short_title_video["title"] = "Quick Update"
    long_title_video = next(v for v in videos if v["youtube_id"] == "video008mock")
    long_title_video["title"] = (
        "Beta Bytes: An Extremely Long and Detailed Title About Something Very "
        "Specific That Will Definitely Wrap Across Two Full Lines #8"
    )

    long_description_video = next(v for v in videos if v["youtube_id"] == "video012mock")
    long_description_video["description"] = (
        "Synthetic mock description for the \"First Look\" episode of Gamma Grill. "
        "Not real content — generated by Fixtures/mock_server.py for local development, "
        "deliberately made long so the video-detail screen's 4-line \"Show More\"/\"Show Less\" "
        "collapse has something to actually collapse.\n\n"
        "Timeline (synthetic, does not correspond to anything in the 90s sample clip beyond "
        "its own real length): intro at 0:05, the first demo starts around 1:15, and the "
        "wrap-up begins near 1:20 — these mm:ss timestamps should render as tappable links "
        "that seek the player.\n\n"
        "More info and the original synthetic project page: https://example.com/plevi-ta/mock-video "
        "— that bare URL should also linkify. Thanks for watching this placeholder text!"
    )

    return videos, sort_keys


def _build_comments() -> dict[str, list[dict]]:
    """A handful of videos get comments (one with a reply thread, one with
    simple root-only comments); the rest have none, so both the threaded and
    the "Comments not available" empty state are exercisable."""

    def comment(video_id: str, suffix: str, author: str, text: str, *, parent: str = "root",
                likes: int = 0, is_uploader: bool = False, days_ago: float = 1.0) -> dict:
        return {
            "comment_id": f"{video_id}-c{suffix}",
            "comment_text": text,
            "comment_author": author,
            "comment_author_id": f"author-{author.lower().replace(' ', '')}",
            "comment_author_thumbnail": f"/cache/comments/{author.lower().replace(' ', '')}.jpg",
            "comment_author_is_uploader": is_uploader,
            "comment_time_text": f"{int(days_ago)} day{'s' if days_ago != 1 else ''} ago",
            "comment_timestamp": 1_757_000_000.0 - days_ago * 86_400,
            "comment_likecount": likes,
            "comment_is_favorited": False,
            "comment_parent": parent,
        }

    by_video: dict[str, list[dict]] = {}

    # video001mock: already-watched video, a couple of simple root comments,
    # no replies — covers "threaded but flat" alongside video012mock's tree.
    by_video["video001mock"] = [
        comment("video001mock", "1", "Ari Sampler", "Nice recap, thanks for putting this together.", likes=3, days_ago=6),
        comment("video001mock", "2", "Milo Frame", "The transitions in the middle section were smooth.", likes=1, days_ago=5),
    ]

    # video012mock: the "resume/partial watch" test video (see duration
    # override above) — a rich thread, including one reply from the
    # channel's own uploader (comment_author_is_uploader) and a nested reply.
    by_video["video012mock"] = [
        comment("video012mock", "1", "Ada Synth", "Great episode, loved the pacing here!", likes=12, days_ago=2),
        comment("video012mock", "2", "Bo Renderer", "Second this, the editing around the middle is slick.", likes=4, days_ago=3),
        comment("video012mock", "3", "Gamma Grill", "Thanks everyone, more coming soon!", parent="video012mock-c1", likes=6, is_uploader=True, days_ago=1),
        comment("video012mock", "4", "Cy Buffer", "Agreed!", parent="video012mock-c1", likes=1, days_ago=1),
        comment("video012mock", "5", "Dee Vector", "Can you go deeper on the setup shown earlier next time?", likes=2, days_ago=4),
    ]

    # video013mock: the "watch to completion" test video — deliberately no
    # comments, so this phase's manual pass also exercises the empty state.

    by_video["video002mock"] = [
        comment(
            "video002mock",
            str(index),
            f"Viewer {index:02d}",
            f"Comment number {index} — plenty of these, to scroll past.",
            likes=(index * 3) % 17,
            days_ago=float(index % 30 + 1),
        )
        for index in range(1, 39)
    ]

    return by_video


COMMENTS_BY_VIDEO: dict[str, list[dict]] = _build_comments()


def _playlist_video(youtube_id: str) -> dict:
    return next(v for v in VIDEOS if v["youtube_id"] == youtube_id)


def _playlist_entry(youtube_id: str, idx: int) -> dict:
    video = _playlist_video(youtube_id)
    return {
        "youtube_id": youtube_id,
        "title": video["title"],
        "uploader": video["channel"]["channel_name"],
        "idx": idx,
        "downloaded": True,
    }


def _playlist_entry_not_downloaded(youtube_id: str, idx: int, title: str, uploader: str) -> dict:
    return {
        "youtube_id": youtube_id,
        "title": title,
        "uploader": uploader,
        "idx": idx,
        "downloaded": False,
    }


def _build_playlists() -> list[dict]:
    alpha_ids = ["video001mock", "video004mock", "video007mock", "video010mock", "video013mock", "video016mock"]
    gamma_ids = ["video003mock", "video006mock", "video009mock", "video012mock", "video015mock"]
    custom_ids = ["video012mock", "video013mock", "video014mock", "video016mock", "video018mock"]

    playlists = [
        {
            "playlist_id": "playlist_alpha_uploads",
            "playlist_name": "Alpha Aerials — Uploads",
            "playlist_channel": "Alpha Aerials",
            "playlist_channel_id": "channel_alpha01",
            "playlist_description": (
                "Synthetic mock playlist: every Alpha Aerials upload the mock catalog knows about. "
                "Not real content — generated by Fixtures/mock_server.py for local development."
            ),
            "playlist_thumbnail": "/cache/playlists/playlist_alpha_uploads/thumb.jpg",
            "playlist_subscribed": True,
            "playlist_type": "regular",
            "playlist_sort_order": "playlist",
            "playlist_entries": [_playlist_entry(vid, idx) for idx, vid in enumerate(alpha_ids)] + [
                _playlist_entry_not_downloaded("zzNeverDL01mock", len(alpha_ids), "Behind the Scenes: Drone Rig Build", "Alpha Aerials"),
                _playlist_entry_not_downloaded("zzNeverDL02mock", len(alpha_ids) + 1, "Live Q&A — Winter Flight Season", "Alpha Aerials"),
                _playlist_entry_not_downloaded("zzNeverDL03mock", len(alpha_ids) + 2, "Members-Only Bloopers Reel", "Alpha Aerials"),
            ],
        },
        {
            "playlist_id": "playlist_gamma_recipes",
            "playlist_name": "Gamma Grill — Recipes",
            "playlist_channel": "Gamma Grill Home Cooking & Recipe Archive",
            "playlist_channel_id": "channel_gamma03",
            "playlist_description": (
                "Synthetic mock playlist: a themed subset of Gamma Grill uploads. Not real content — "
                "generated by Fixtures/mock_server.py for local development."
            ),
            "playlist_thumbnail": "/cache/playlists/playlist_gamma_recipes/thumb.jpg",
            "playlist_subscribed": False,
            "playlist_type": "regular",
            "playlist_sort_order": "playlist",
            "playlist_entries": [_playlist_entry(vid, idx) for idx, vid in enumerate(gamma_ids)],
        },
        {
            "playlist_id": "playlist_custom_favorites",
            "playlist_name": "Cross-Channel Favorites: The Ultimate Highlights Compilation",
            "playlist_channel": None,
            "playlist_channel_id": None,
            "playlist_description": (
                "Synthetic mock custom playlist spanning multiple channels, deliberately built from "
                "never-watched videos so Play All / auto-advance has a real chain to walk through end "
                "to end. Not real content — generated by Fixtures/mock_server.py for local development."
            ),
            "playlist_thumbnail": "/cache/playlists/playlist_custom_favorites/thumb.jpg",
            "playlist_subscribed": True,
            "playlist_type": "custom",
            "playlist_sort_order": "custom",
            "playlist_entries": [_playlist_entry(vid, idx) for idx, vid in enumerate(custom_ids)],
        },
    ]

    for playlist in playlists:
        for entry in playlist["playlist_entries"]:
            video = next((v for v in VIDEOS if v["youtube_id"] == entry["youtube_id"]), None)
            if video is not None:
                video["playlist"].append(playlist["playlist_id"])

    return playlists


PLAYLIST_PAGE_SIZE = 2


def _png_chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def _png_bytes(width: int, height: int, rgb: tuple[int, int, int]) -> bytes:
    """A minimal, valid solid-color PNG built by hand (stdlib `zlib` only —
    no imaging library available). Content-Type is what tells a real client
    this is a PNG; the mock's `/cache/...` URLs use a `.jpg`-looking path
    only because that is what a real TA instance's paths look like."""
    signature = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)  # 8-bit/channel, RGB
    raw_row = b"\x00" + bytes(rgb) * width  # filter-type byte (None) + pixels
    raw = raw_row * height
    idat = zlib.compress(raw, level=6)
    return signature + _png_chunk(b"IHDR", ihdr) + _png_chunk(b"IDAT", idat) + _png_chunk(b"IEND", b"")


def _color_for_path(path: str) -> tuple[int, int, int]:
    """Deterministic per-path color so different videos/channels are
    visibly distinguishable thumbnails without needing real images."""
    digest = hashlib.sha256(path.encode("utf-8")).digest()
    return (64 + digest[0] % 160, 64 + digest[1] % 160, 64 + digest[2] % 160)


# --- In-memory state (reset on every process restart) ----------------------
_state_lock = threading.Lock()
sessions: dict[str, dict[str, str]] = {}  # sessionid -> {"username", "csrftoken"}
user_config: dict = dict(DEFAULT_USER_CONFIG)
VIDEOS, VIDEO_SORT_KEYS = _build_videos()
# Built only now that VIDEOS exists (`_build_playlists` looks videos up by
# id, and also mutates each referenced video's `playlist` list in place —
# see its own doc comment above).
PLAYLISTS: list[dict] = _build_playlists()
DOWNLOAD_STATUS: dict[str, str] = {}
# Video ids that currently have a download-queue entry. Empty at startup: every video in
# VIDEOS has already been downloaded, and a downloaded video has left the queue — which is
# what makes plain "ignore" 404 for them, as it does on a real server.
DOWNLOAD_QUEUE: set[str] = set()


def _json_bytes(payload) -> bytes:
    return json.dumps(payload).encode("utf-8")


class MockHandler(BaseHTTPRequestHandler):
    server_version = "PleviTAMockServer/0.1"

    # Quiet, single-line request logging instead of BaseHTTPRequestHandler's
    # default two-line format.
    def log_message(self, format: str, *args) -> None:  # noqa: A002
        sys.stderr.write("mock_server: " + (format % args) + "\n")

    # -- auth helpers --------------------------------------------------
    def _authed_username(self) -> str | None:
        auth = self.headers.get("Authorization", "")
        if auth.startswith("Token "):
            token = auth.removeprefix("Token ").strip()
            if token == MOCK_TOKEN:
                return MOCK_USERNAME
            return None

        session_id = self._cookie("sessionid")
        if session_id:
            with _state_lock:
                session = sessions.get(session_id)
            if session:
                return session["username"]
        return None

    def _cookie(self, name: str) -> str | None:
        raw = self.headers.get("Cookie")
        if not raw:
            return None
        for part in raw.split(";"):
            part = part.strip()
            if part.startswith(name + "="):
                return part[len(name) + 1:]
        return None

    def _require_auth(self) -> str | None:
        username = self._authed_username()
        if username is None:
            self._send_json(
                HTTPStatus.UNAUTHORIZED,
                {"detail": "Authentication credentials were not provided."},
            )
        return username

    # -- response helpers ------------------------------------------------
    def _send_json(self, status: HTTPStatus, payload, extra_headers: list[tuple[str, str]] | None = None) -> None:
        body = _json_bytes(payload)
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for key, value in extra_headers or []:
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def _send_no_content(self, extra_headers: list[tuple[str, str]] | None = None) -> None:
        self.send_response(HTTPStatus.NO_CONTENT)
        self.send_header("Content-Length", "0")
        for key, value in extra_headers or []:
            self.send_header(key, value)
        self.end_headers()

    def _read_json_body(self) -> dict:
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length == 0:
            return {}
        raw = self.rfile.read(length)
        if not raw:
            return {}
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return {}

    def _query_params(self) -> dict[str, str]:
        parsed = parse_qs(urlsplit(self.path).query)
        return {key: values[0] for key, values in parsed.items() if values}

    # -- routing -----------------------------------------------------------
    def do_GET(self) -> None:  # noqa: N802
        path = urlsplit(self.path).path
        if path == "/api/ping/":
            self._handle_ping()
        elif path == "/api/appsettings/token/":
            self._handle_get_token()
        elif path == "/api/user/me/":
            self._handle_get_user_config()
        elif path == "/api/user/account/":
            self._handle_get_account()
        elif path == "/api/video/":
            self._handle_video_list()
        elif path.startswith("/api/video/") and path.endswith("/comment/"):
            self._handle_video_comments(self._video_id_from(path, suffix="/comment/"))
        elif path.startswith("/api/video/") and path.endswith("/similar/"):
            self._handle_video_similar(self._video_id_from(path, suffix="/similar/"))
        elif path.startswith("/api/video/") and path.endswith("/nav/"):
            self._handle_video_nav(self._video_id_from(path, suffix="/nav/"))
        elif path.startswith("/api/video/") and path.endswith("/"):
            self._handle_video_detail(path[len("/api/video/"):-1])
        elif path == "/api/channel/":
            self._handle_channel_list()
        elif path.startswith("/api/channel/") and path.endswith("/aggs/"):
            self._handle_channel_aggs(self._channel_id_from(path, suffix="/aggs/"))
        elif path.startswith("/api/channel/") and path.endswith("/nav/"):
            self._handle_channel_nav(self._channel_id_from(path, suffix="/nav/"))
        elif path.startswith("/api/channel/") and path.endswith("/"):
            self._handle_channel_detail(path[len("/api/channel/"):-1])
        elif path == "/api/playlist/":
            self._handle_playlist_list()
        elif path.startswith("/api/playlist/") and path.endswith("/"):
            self._handle_playlist_detail(path[len("/api/playlist/"):-1])
        elif path == "/api/search/":
            self._handle_search()
        elif path.startswith("/media/"):
            self._handle_media(path)
        elif path.startswith("/cache/"):
            self._handle_cache_image(path)
        else:
            self._send_json(HTTPStatus.NOT_FOUND, {"detail": "Not found."})

    def do_POST(self) -> None:  # noqa: N802
        path = urlsplit(self.path).path
        if path == "/api/user/login/":
            self._handle_login()
        elif path == "/api/user/logout/":
            self._handle_logout()
        elif path == "/api/user/me/":
            self._handle_post_user_config()
        elif path == "/api/watched/":
            self._handle_set_watched()
        elif path.startswith("/api/video/") and path.endswith("/progress/"):
            self._handle_set_progress(self._video_id_from(path, suffix="/progress/"))
        elif path.startswith("/api/download/") and path.endswith("/"):
            self._handle_set_download_status(path[len("/api/download/"):-1])
        elif path.startswith("/api/playlist/") and path.endswith("/"):
            self._handle_playlist_action(path[len("/api/playlist/"):-1])
        else:
            self._send_json(HTTPStatus.NOT_FOUND, {"detail": "Not found."})

    def do_DELETE(self) -> None:  # noqa: N802
        path = urlsplit(self.path).path
        if path.startswith("/api/video/") and path.endswith("/progress/"):
            self._handle_clear_progress(self._video_id_from(path, suffix="/progress/"))
        elif path.startswith("/api/video/") and path.endswith("/"):
            self._handle_delete_video(path[len("/api/video/"):-1])
        else:
            self._send_json(HTTPStatus.NOT_FOUND, {"detail": "Not found."})

    @staticmethod
    def _video_id_from(path: str, *, suffix: str) -> str:
        return path[len("/api/video/"):-len(suffix)]

    @staticmethod
    def _channel_id_from(path: str, *, suffix: str) -> str:
        return path[len("/api/channel/"):-len(suffix)]

    # -- handlers ------------------------------------------------------
    def _handle_login(self) -> None:
        body = self._read_json_body()
        username = body.get("username", "")
        password = body.get("password", "")
        remember_me = body.get("remember_me") == "on"

        if username != MOCK_USERNAME or password != MOCK_PASSWORD:
            self._send_json(HTTPStatus.BAD_REQUEST, {"detail": "Wrong username or password."})
            return

        session_id = secrets.token_hex(16)
        csrf_token = secrets.token_hex(16)
        with _state_lock:
            sessions[session_id] = {"username": username, "csrftoken": csrf_token}

        max_age = 60 * 60 * 24 * (365 if remember_me else 2)
        self._send_no_content(
            extra_headers=[
                ("Set-Cookie", f"sessionid={session_id}; Path=/; HttpOnly; Max-Age={max_age}"),
                ("Set-Cookie", f"csrftoken={csrf_token}; Path=/; Max-Age={max_age}"),
            ]
        )

    def _handle_logout(self) -> None:
        session_id = self._cookie("sessionid")
        if session_id:
            with _state_lock:
                sessions.pop(session_id, None)
        self._send_no_content()

    def _handle_get_token(self) -> None:
        if self._require_auth() is None:
            return
        self._send_json(HTTPStatus.OK, {"token": MOCK_TOKEN})

    def _handle_ping(self) -> None:
        if self._require_auth() is None:
            return
        self._send_json(
            HTTPStatus.OK,
            {"response": "pong", "user": 1, "version": MOCK_VERSION, "ta_update": False},
        )

    def _handle_get_account(self) -> None:
        username = self._require_auth()
        if username is None:
            return
        self._send_json(
            HTTPStatus.OK,
            {"id": 1, "username": username, "is_staff": True, "is_superuser": True},
        )

    def _handle_get_user_config(self) -> None:
        if self._require_auth() is None:
            return
        with _state_lock:
            config = dict(user_config)
        self._send_json(HTTPStatus.OK, config)

    def _handle_post_user_config(self) -> None:
        if self._require_auth() is None:
            return
        partial = self._read_json_body()
        with _state_lock:
            user_config.update(partial)
            config = dict(user_config)
        self._send_json(HTTPStatus.OK, config)

    def _handle_video_list(self) -> None:
        if self._require_auth() is None:
            return
        params = self._query_params()
        watch = params.get("watch")
        sort = params.get("sort", "downloaded")
        order = params.get("order", "desc")
        vtype = params.get("type")
        channel = params.get("channel")
        playlist_id = params.get("playlist")
        try:
            page = int(params.get("page", "1"))
        except ValueError:
            page = 1

        with _state_lock:
            items = list(VIDEOS)

        if channel:
            items = [v for v in items if v["channel"]["channel_id"] == channel]
        if playlist_id:
            playlist = self._find_playlist(playlist_id)
            entry_ids = {e["youtube_id"] for e in playlist["playlist_entries"]} if playlist else set()
            items = [v for v in items if v["youtube_id"] in entry_ids]
        if vtype:
            items = [v for v in items if v["vid_type"] == vtype]
        if watch == "watched":
            items = [v for v in items if v["player"]["watched"]]
        elif watch == "unwatched":
            items = [v for v in items if not v["player"]["watched"]]
        elif watch == "continue":
            items = [v for v in items if not v["player"]["watched"] and v["player"]["position"]]

        sort_key = sort if sort in ("published", "downloaded", "views", "likes", "duration", "filesize") else "downloaded"
        items.sort(key=lambda v: VIDEO_SORT_KEYS[v["youtube_id"]][sort_key], reverse=(order != "asc"))

        total = len(items)
        last_page = max(1, -(-total // VIDEO_PAGE_SIZE))  # ceil division
        page = max(1, min(page, last_page))
        start = (page - 1) * VIDEO_PAGE_SIZE
        page_items = items[start:start + VIDEO_PAGE_SIZE]

        paginate = {
            "page_size": VIDEO_PAGE_SIZE,
            "page_from": start,
            "prev_pages": list(range(1, page)),
            "current_page": page,
            "max_hits": False,
            "last_page": last_page,
            "next_pages": list(range(page + 1, last_page + 1)),
            "total_hits": total,
        }
        self._send_json(HTTPStatus.OK, {"data": page_items, "paginate": paginate})

    def _handle_video_detail(self, youtube_id: str) -> None:
        if self._require_auth() is None:
            return
        if not youtube_id or "/" in youtube_id:
            self._send_json(HTTPStatus.NOT_FOUND, {"detail": "Not found."})
            return
        with _state_lock:
            video = next((v for v in VIDEOS if v["youtube_id"] == youtube_id), None)
        if video is None:
            self._send_json(HTTPStatus.NOT_FOUND, {"detail": "Not found."})
            return
        self._send_json(HTTPStatus.OK, video)

    def _handle_channel_list(self) -> None:
        if self._require_auth() is None:
            return
        params = self._query_params()
        subscribed_only = params.get("filter") == "subscribed"
        try:
            page = int(params.get("page", "1"))
        except ValueError:
            page = 1

        items = [dict(c) for c in CHANNELS]
        if subscribed_only:
            items = [c for c in items if c["channel_subscribed"]]

        total = len(items)
        last_page = max(1, -(-total // CHANNEL_PAGE_SIZE))
        page = max(1, min(page, last_page))
        start = (page - 1) * CHANNEL_PAGE_SIZE
        page_items = items[start:start + CHANNEL_PAGE_SIZE]

        paginate = {
            "page_size": CHANNEL_PAGE_SIZE,
            "page_from": start,
            "prev_pages": list(range(1, page)),
            "current_page": page,
            "max_hits": False,
            "last_page": last_page,
            "next_pages": list(range(page + 1, last_page + 1)),
            "total_hits": total,
        }
        self._send_json(HTTPStatus.OK, {"data": page_items, "paginate": paginate})

    @staticmethod
    def _find_channel(channel_id: str) -> dict | None:
        return next((c for c in CHANNELS if c["channel_id"] == channel_id), None)

    def _handle_channel_detail(self, channel_id: str) -> None:
        if self._require_auth() is None:
            return
        channel = self._find_channel(channel_id)
        if channel is None:
            self._send_json(HTTPStatus.NOT_FOUND, {"detail": "Not found."})
            return
        self._send_json(HTTPStatus.OK, channel)

    def _handle_channel_aggs(self, channel_id: str) -> None:
        if self._require_auth() is None:
            return
        if self._find_channel(channel_id) is None:
            self._send_json(HTTPStatus.NOT_FOUND, {"detail": "Not found."})
            return
        with _state_lock:
            channel_videos = [v for v in VIDEOS if v["channel"]["channel_id"] == channel_id]
        total_items = len(channel_videos)
        total_size = sum(v["media_size"] for v in channel_videos)
        total_duration = sum(v["player"]["duration"] for v in channel_videos)
        self._send_json(
            HTTPStatus.OK,
            {"total_items": total_items, "total_size": total_size, "total_duration": total_duration},
        )

    def _handle_channel_nav(self, channel_id: str) -> None:
        if self._require_auth() is None:
            return
        if self._find_channel(channel_id) is None:
            self._send_json(HTTPStatus.NOT_FOUND, {"detail": "Not found."})
            return
        with _state_lock:
            vid_types = {v["vid_type"] for v in VIDEOS if v["channel"]["channel_id"] == channel_id}
        has_playlists = any(p["playlist_channel_id"] == channel_id for p in PLAYLISTS)
        self._send_json(
            HTTPStatus.OK,
            {
                "videos": "videos" in vid_types,
                "streams": "streams" in vid_types,
                "shorts": "shorts" in vid_types,
                "playlists": has_playlists,
            },
        )

    @staticmethod
    def _find_playlist(playlist_id: str) -> dict | None:
        return next((p for p in PLAYLISTS if p["playlist_id"] == playlist_id), None)

    def _handle_playlist_list(self) -> None:
        # GET /api/playlist/ — query: page, subscribed=true, type (regular|custom), channel=<id>.
        if self._require_auth() is None:
            return
        params = self._query_params()
        subscribed_only = params.get("subscribed") == "true"
        type_filter = params.get("type")
        channel_id = params.get("channel")
        try:
            page = int(params.get("page", "1"))
        except ValueError:
            page = 1

        items = [dict(p) for p in PLAYLISTS]
        if subscribed_only:
            items = [p for p in items if p["playlist_subscribed"]]
        if type_filter in ("regular", "custom"):
            items = [p for p in items if p["playlist_type"] == type_filter]
        if channel_id:
            items = [p for p in items if p["playlist_channel_id"] == channel_id]

        total = len(items)
        last_page = max(1, -(-total // PLAYLIST_PAGE_SIZE))
        page = max(1, min(page, last_page))
        start = (page - 1) * PLAYLIST_PAGE_SIZE
        page_items = items[start:start + PLAYLIST_PAGE_SIZE]

        paginate = {
            "page_size": PLAYLIST_PAGE_SIZE,
            "page_from": start,
            "prev_pages": list(range(1, page)),
            "current_page": page,
            "max_hits": False,
            "last_page": last_page,
            "next_pages": list(range(page + 1, last_page + 1)),
            "total_hits": total,
        }
        self._send_json(HTTPStatus.OK, {"data": page_items, "paginate": paginate})

    def _handle_playlist_detail(self, playlist_id: str) -> None:
        if self._require_auth() is None:
            return
        playlist = self._find_playlist(playlist_id)
        if playlist is None:
            self._send_json(HTTPStatus.NOT_FOUND, {"detail": "Not found."})
            return
        self._send_json(HTTPStatus.OK, playlist)

    def _handle_search(self) -> None:
        # `GET /api/search/?query=<text>`.
        if self._require_auth() is None:
            return
        params = self._query_params()
        query = params.get("query", "").strip()

        video_results: list[dict] = []
        channel_results: list[dict] = []
        playlist_results: list[dict] = []

        if query:
            needle = query.lower()
            with _state_lock:
                video_results = [
                    v for v in VIDEOS
                    if needle in (v.get("title") or "").lower()
                    or needle in (v.get("description") or "").lower()
                ]
            channel_results = [
                c for c in CHANNELS
                if needle in (c.get("channel_name") or "").lower()
                or needle in (c.get("channel_description") or "").lower()
            ]
            playlist_results = [
                p for p in PLAYLISTS
                if needle in (p.get("playlist_name") or "").lower()
                or needle in (p.get("playlist_description") or "").lower()
            ]

        self._send_json(
            HTTPStatus.OK,
            {
                "results": {
                    "video_results": video_results,
                    "channel_results": channel_results,
                    "playlist_results": playlist_results,
                    "fulltext_results": [],
                }
            },
        )

    def _handle_set_watched(self) -> None:
        # `POST /api/watched/ { id, is_watched }` — `id` can be a video, channel, or playlist id.
        if self._require_auth() is None:
            return
        body = self._read_json_body()
        target_id = body.get("id")
        is_watched = bool(body.get("is_watched"))

        def apply(video: dict) -> None:
            video["player"]["watched"] = is_watched
            if is_watched:
                # A fully-watched video is no longer "in progress" — keeps
                # `watch=continue` consistent with the just-applied state.
                video["player"]["position"] = None
                video["player"]["progress"] = None

        with _state_lock:
            video = next((v for v in VIDEOS if v["youtube_id"] == target_id), None)
            if video is not None:
                apply(video)
            elif self._find_channel(target_id) is not None:
                for v in VIDEOS:
                    if v["channel"]["channel_id"] == target_id:
                        apply(v)
        self._send_no_content()

    def _handle_video_comments(self, youtube_id: str) -> None:
        if self._require_auth() is None:
            return
        self._send_json(HTTPStatus.OK, COMMENTS_BY_VIDEO.get(youtube_id, []))

    def _handle_video_similar(self, youtube_id: str) -> None:
        if self._require_auth() is None:
            return
        with _state_lock:
            video = next((v for v in VIDEOS if v["youtube_id"] == youtube_id), None)
            if video is None:
                self._send_json(HTTPStatus.NOT_FOUND, {"detail": "Not found."})
                return
            channel_id = video["channel"]["channel_id"]
            same_channel = [v for v in VIDEOS if v["youtube_id"] != youtube_id and v["channel"]["channel_id"] == channel_id]
            other_channel = [v for v in VIDEOS if v["youtube_id"] != youtube_id and v["channel"]["channel_id"] != channel_id]
            candidates = (same_channel + other_channel)[:6]
        self._send_json(HTTPStatus.OK, candidates)

    def _handle_video_nav(self, youtube_id: str) -> None:
        if self._require_auth() is None:
            return
        entries: list[dict] = []
        with _state_lock:
            for playlist in PLAYLISTS:
                downloaded = [e for e in playlist["playlist_entries"] if e["downloaded"]]
                position = next((i for i, e in enumerate(downloaded) if e["youtube_id"] == youtube_id), None)
                if position is None:
                    continue
                # Real TA omits a playlist with only one downloaded item
                # entirely (YoutubePlaylist.build_nav returns without
                # assigning self.nav) — nothing to navigate to.
                if len(downloaded) < 2:
                    continue
                previous_entry = downloaded[position - 1] if position > 0 else None
                next_entry = downloaded[position + 1] if position < len(downloaded) - 1 else None

                def nav_video(entry, idx):
                    if entry is None:
                        return None
                    video = next((v for v in VIDEOS if v["youtube_id"] == entry["youtube_id"]), None)
                    return {
                        "youtube_id": entry["youtube_id"],
                        "title": entry["title"],
                        "uploader": entry.get("uploader") or (video or {}).get("channel", {}).get("channel_name"),
                        "idx": idx,
                        "downloaded": True,
                        "vid_thumb": (video or {}).get("vid_thumb_url"),
                    }

                entries.append({
                    "playlist_meta": {
                        "current_idx": position,
                        "playlist_id": playlist["playlist_id"],
                        "playlist_name": playlist["playlist_name"],
                        "playlist_channel": playlist.get("playlist_channel"),
                    },
                    "playlist_previous": nav_video(previous_entry, position - 1),
                    "playlist_next": nav_video(next_entry, position + 1),
                })
        self._send_json(HTTPStatus.OK, entries)

    def _handle_set_progress(self, youtube_id: str) -> None:
        if self._require_auth() is None:
            return
        body = self._read_json_body()
        try:
            position = float(body.get("position", 0))
        except (TypeError, ValueError):
            position = 0.0
        with _state_lock:
            video = next((v for v in VIDEOS if v["youtube_id"] == youtube_id), None)
            if video is None:
                self._send_json(HTTPStatus.NOT_FOUND, {"detail": "Not found."})
                return
            duration = video["player"]["duration"] or 0
            video["player"]["position"] = position
            video["player"]["progress"] = round((position / duration) * 100, 1) if duration else 0.0
            player = dict(video["player"])
        self._send_json(HTTPStatus.OK, player)

    def _handle_clear_progress(self, youtube_id: str) -> None:
        if self._require_auth() is None:
            return
        with _state_lock:
            video = next((v for v in VIDEOS if v["youtube_id"] == youtube_id), None)
            if video is not None:
                video["player"]["position"] = None
                video["player"]["progress"] = None
        self._send_no_content()

    def _handle_delete_video(self, youtube_id: str) -> None:
        if self._require_auth() is None:
            return
        with _state_lock:
            video = next((v for v in VIDEOS if v["youtube_id"] == youtube_id), None)
            if video is None:
                self._send_json(HTTPStatus.NOT_FOUND, {"detail": "Not found."})
                return
            VIDEOS.remove(video)
            for playlist in PLAYLISTS:
                playlist["playlist_entries"] = [
                    entry for entry in playlist["playlist_entries"] if entry["youtube_id"] != youtube_id
                ]
        self._send_no_content()

    def _handle_set_download_status(self, youtube_id: str) -> None:
        """POST /api/download/<id>/ — mirrors TA's DownloadApiView.post.

        The distinction this models is load-bearing, and the mock not modelling it is
        why the app shipped an ignore that could never work. Real TA looks the video up
        in the download queue and 404s "Download item not found" when it isn't there,
        EXCEPT for "ignore-force", which is checked before that lookup and creates the
        entry already ignored. A video in VIDEOS is one that finished downloading and
        left the queue, so plain "ignore" must 404 for it here exactly as it does live.
        """
        if self._require_auth() is None:
            return
        body = self._read_json_body()
        status = body.get("status")
        if status not in ("pending", "ignore", "ignore-force", "priority"):
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": "Invalid status"})
            return
        with _state_lock:
            if status != "ignore-force" and youtube_id not in DOWNLOAD_QUEUE:
                self._send_json(HTTPStatus.NOT_FOUND, {"error": "Download item not found"})
                return
            DOWNLOAD_QUEUE.add(youtube_id)
            DOWNLOAD_STATUS[youtube_id] = "ignore" if status == "ignore-force" else status
        self._send_no_content()

    def _handle_playlist_action(self, playlist_id: str) -> None:
        if self._require_auth() is None:
            return
        body = self._read_json_body()
        video_id = body.get("video_id")
        with _state_lock:
            playlist = next((p for p in PLAYLISTS if p["playlist_id"] == playlist_id), None)
            if playlist is None:
                self._send_json(HTTPStatus.NOT_FOUND, {"detail": "Not found."})
                return
            video = next((v for v in VIDEOS if v["youtube_id"] == video_id), None)
            if video is None:
                self._send_json(HTTPStatus.NOT_FOUND, {"detail": "Not found."})
                return
            # `_build_playlists` back-fills both sides of this relationship at startup (its own doc comment).
            already_present = any(e["youtube_id"] == video_id for e in playlist["playlist_entries"])
            if not already_present:
                idx = len(playlist["playlist_entries"])
                playlist["playlist_entries"].append(_playlist_entry(video_id, idx))
            if playlist_id not in video["playlist"]:
                video["playlist"].append(playlist_id)
        self._send_no_content()

    def _handle_cache_image(self, path: str) -> None:
        if path in _UNCACHED_CHANNEL_ART_PATHS:
            self._send_json(HTTPStatus.NOT_FOUND, {"detail": "Not found."})
            return
        color = _color_for_path(path)
        data = _png_bytes(320, 180, color)
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def _handle_media(self, path: str) -> None:
        # Every /media/<anything> resolves to one of a small handful of synthetic sample files, picked by the requested filename.
        if self._require_auth() is None:
            return

        filename = path.rsplit("/", 1)[-1]
        if filename.endswith(".vtt"):
            data = _SUBTITLE_VTT_BYTES
            content_type = "text/vtt"
        elif filename.startswith(FALLBACK_TEST_VIDEO_ID):
            sample = MEDIA_DIR / "sample_av1_opus.mp4"
            if not sample.is_file():
                self._send_json(HTTPStatus.NOT_FOUND, {"detail": "Not found."})
                return
            data = sample.read_bytes()
            content_type = "video/mp4"
        else:
            sample = MEDIA_DIR / "sample.mp4"
            if not sample.is_file():
                self._send_json(HTTPStatus.NOT_FOUND, {"detail": "Not found."})
                return
            data = sample.read_bytes()
            content_type = "video/mp4"
        total = len(data)

        range_header = self.headers.get("Range")
        if range_header and range_header.startswith("bytes="):
            try:
                start_str, _, end_str = range_header[len("bytes="):].partition("-")
                start = int(start_str) if start_str else 0
                end = int(end_str) if end_str else total - 1
                end = min(end, total - 1)
                if start > end or start >= total:
                    raise ValueError("unsatisfiable range")
            except ValueError:
                self.send_response(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
                self.send_header("Content-Range", f"bytes */{total}")
                self.end_headers()
                return

            chunk = data[start:end + 1]
            self.send_response(HTTPStatus.PARTIAL_CONTENT)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Range", f"bytes {start}-{end}/{total}")
            self.send_header("Content-Length", str(len(chunk)))
            self.send_header("Accept-Ranges", "bytes")
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(chunk)
            return

        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(total))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def do_HEAD(self) -> None:  # noqa: N802
        path = urlsplit(self.path).path
        if path.startswith("/media/"):
            self._handle_media(path)
        elif path.startswith("/cache/"):
            self._handle_cache_image(path)
        else:
            self.send_response(HTTPStatus.METHOD_NOT_ALLOWED)
            self.end_headers()


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8081
    server = ThreadingHTTPServer(("127.0.0.1", port), MockHandler)
    print(f"mock_server: serving synthetic Tube Archivist fixtures on http://127.0.0.1:{port}")
    print(f"mock_server: mock login is username={MOCK_USERNAME!r} password={MOCK_PASSWORD!r} (synthetic, local-only)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
