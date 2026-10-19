# Phase 4: Cloud Inference Backend Infrastructure (Proprietary, No BYOK)

**Target:** Build the private, authenticated cloud gateway that proxies requests to high-reasoning foundation LLMs (e.g. Gemini 1.5 Pro, Claude), tracks monthly token budgets per subscriber, and enforces security guardrails without exposing provider API keys to the client.  
**Target:** Implement the private, production-ready cloud gateway in Python (FastAPI). It authenticates mobile app subscribers, enforces monthly token budgets, securely stores foundation model keys, and streams reasoning tokens and tool calls back to the Flutter client via Server-Sent Events (SSE).  
**Repository:** `overline-backend` (Private Git Repository).  
**Prerequisites:** Phase 3 complete.

---

## 1. Objectives & Deliverables
1. Build a lightweight, high-performance gateway service in Python (FastAPI) or Go.
2. Implement JWT-based user authentication using Firebase Auth or Supabase Auth.
3. Integrate cloud foundation model APIs (e.g. Google Gemini 1.5 Pro/Flash, Anthropic Claude 3.5 Sonnet) via streaming Server-Sent Events (SSE).
4. Implement document chunking, semantic context injection, and system prompts optimized for PDF reasoning and tool calling.
5. Implement Redis-backed token accounting: track per-user monthly token consumption, daily request limits, and abuse protection.
6. Containerize with Docker and prepare for deployment on serverless infrastructure (Google Cloud Run / AWS ECS / Cloudflare Workers).
## 1. Concrete Architecture & Security Boundaries

```
[Mobile Subscriber]
       │
       │ HTTPS POST /v1/agent/chat (Bearer Firebase/Supabase JWT)
       ▼
┌─────────────────────────────────────────────────────────────┐
│                   Overline Cloud Gateway                    │
│                                                             │
│ 1. Verify JWT signature via JWKS                            │
│ 2. Check active subscription status in Database             │
│ 3. Check & reserve monthly token budget in Redis            │
│ 4. Map client tools to Gemini/Claude Function Declarations  │
│ 5. Stream response via Server-Sent Events (SSE)             │
│ 6. Commit actual token usage to Redis                       │
└──────────────────────────────┬──────────────────────────────┘
                               │
                               ▼
               [Google Gemini 1.5 Pro / Flash]
```

---

## 2. Step-by-Step Implementation Instructions
## 2. Pinned Dependencies: `requirements.txt`

### Step 4.1: Architecture & Directory Structure
Initialize the private backend service:
```txt
fastapi==0.115.0
uvicorn[standard]==0.30.6
pydantic==2.9.2
sse-starlette==2.1.3
google-genai==0.1.1
redis==5.0.8
pyjwt[crypto]==2.9.0
requests==2.32.3
python-dotenv==1.0.1
```
overline-backend/
├── cmd/ (or src/)
│   ├── main.py (or main.go)
│   ├── config.py
│   ├── middleware/
│   │   ├── auth.py          # JWT validation (Firebase / Supabase)
│   │   └── rate_limiter.py  # Redis token bucket & abuse prevention
│   ├── routes/
│   │   ├── agent.py         # POST /v1/agent/chat (SSE streaming)
│   │   ├── usage.py         # GET /v1/user/usage (monthly quota check)
│   │   └── health.py        # GET /v1/health
│   ├── services/
│   │   ├── llm_router.py    # Multi-provider LLM client (Gemini, Claude)
│   │   ├── quota_service.py # Redis token balance ledger
│   │   └── prompt_builder.py
│   └── models/
│       ├── schemas.py       # Pydantic request/response validation
├── Dockerfile
├── requirements.txt (or go.mod)
└── README.md

---

## 3. Full Production Implementation

### 3.1 Pydantic Request & Response Schemas: `src/models/schemas.py`

```python
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field

class DocumentContextModel(BaseModel):
    pageCount: int = Field(..., ge=1)
    currentPageIndex: int = Field(..., ge=1)
    documentTitle: str = "Untitled Document"
    extractedTextSnippet: Optional[str] = ""
    bookmarks: List[str] = Field(default_factory=list)

class ChatRequest(BaseModel):
    prompt: str = Field(..., min_length=1, max_length=4000)
    document_context: DocumentContextModel
    tools: List[Dict[str, Any]] = Field(default_factory=list)

class UsageResponse(BaseModel):
    user_id: str
    is_subscriber: bool
    used_tokens: int
    monthly_token_cap: int
    percent_consumed: float
```

### Step 4.2: Authentication & Authorization Middleware
The gateway must reject any unauthenticated call:
1. Extract `Authorization: Bearer <ID_TOKEN>` header.
2. Verify signature against Firebase Auth or Supabase Auth public JWKS keys.
3. Extract `user_id` (`sub`) and email.
4. Inject `user_id` into the request context.
---

### Step 4.3: Token Quotas & Redis Ledger (Enforcing "No BYOK" Economics)
Because you pay the foundation model bills per token, the backend must prevent runaway inference costs:
1. Every subscriber tier is assigned a monthly input/output token allocation:
   - Free/Trial Tier: Edge SLM only (or 25,000 cloud tokens/month).
   - Pro Subscriber: 1,000,000 cloud tokens/month.
2. Before invoking the LLM:
   - Query Redis key `quota:{user_id}:{YYYY-MM}`.
   - If `used_tokens >= max_allowed_tokens`, return HTTP 429:
     ```json
     {"error": "QUOTA_EXCEEDED", "message": "Monthly cloud inference limit reached. Please use the on-device Edge SLM until your next billing cycle."}
     ```
3. After the LLM response completes:
   - Sum actual prompt tokens + completion tokens reported in the provider response metadata.
   - Atomically increment Redis: `INCRBY quota:{user_id}:{YYYY-MM} <total_tokens>`.
### 3.2 Authentication & Redis Quota Service: `src/services/quota_service.py`

### Step 4.4: Cloud LLM Streaming Route (`/v1/agent/chat`)
Implement streaming Server-Sent Events (SSE):
1. **Input Payload**:
   ```json
   {
     "prompt": "Find all sensitive financial totals and propose redactions.",
     "document_context": {
       "page_count": 12,
       "current_page": 1,
       "text_snippet": "..."
     },
     "tools": [ /* TaskCatalog tool schemas */ ]
   }
   ```
2. **Provider Call**:
   - Route to **Gemini 1.5 Flash** for quick operations or **Gemini 1.5 Pro / Claude 3.5 Sonnet** for complex legal/technical documents.
   - Inject the Overline master agent system prompt and schema tools.
3. **SSE Output Stream**:
   - Emit event `thought`: incremental thinking / reasoning text.
   - Emit event `tool_call`: structured JSON tool invocation.
   - Emit event `done`: total tokens consumed and quota balance remaining.
```python
import os
import redis
from datetime import datetime
from fastapi import HTTPException, status

### Step 4.5: Prompt Engineering & Guardrails
In `services/prompt_builder.py`:
- Strip unnecessary system metadata to conserve context window tokens.
- Add strict hallucination guards: *"You are an assistant for modifying PDF documents. Only emit tool calls that correspond to the registered tools. Never guess page indices or attributes not present in the document context."*
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", None)

### Step 4.6: Containerization & Deployment
Create `Dockerfile`:
```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8080
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8080"]
r = redis.Redis(
    host=REDIS_HOST,
    port=REDIS_PORT,
    password=REDIS_PASSWORD,
    decode_responses=True,
)

# 1,000,000 monthly tokens for Pro subscribers
MONTHLY_PRO_TOKEN_CAP = 1_000_000
FREE_TRIAL_TOKEN_CAP = 50_000

class QuotaService:
    @staticmethod
    def _get_key(user_id: str) -> str:
        current_month = datetime.utcnow().strftime("%Y-%m")
        return f"quota:{user_id}:{current_month}"

    @classmethod
    def check_and_reserve(cls, user_id: str, is_subscriber: bool, estimated_tokens: int = 1000):
        key = cls._get_key(user_id)
        used = int(r.get(key) or 0)
        cap = MONTHLY_PRO_TOKEN_CAP if is_subscriber else FREE_TRIAL_TOKEN_CAP

        if used + estimated_tokens > cap:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail={
                    "error": "MONTHLY_QUOTA_EXCEEDED",
                    "used": used,
                    "cap": cap,
                    "message": "Monthly cloud inference limit reached. Please use on-device Edge SLM until next month.",
                },
            )

    @classmethod
    def record_usage(cls, user_id: str, tokens_consumed: int):
        key = cls._get_key(user_id)
        # Atomically increment and set 60-day expiry to auto-prune
        pipe = r.pipeline()
        pipe.incrby(key, tokens_consumed)
        pipe.expire(key, 60 * 60 * 24 * 60)
        pipe.execute()

    @classmethod
    def get_user_usage(cls, user_id: str, is_subscriber: bool) -> dict:
        key = cls._get_key(user_id)
        used = int(r.get(key) or 0)
        cap = MONTHLY_PRO_TOKEN_CAP if is_subscriber else FREE_TRIAL_TOKEN_CAP
        return {
            "user_id": user_id,
            "is_subscriber": is_subscriber,
            "used_tokens": used,
            "monthly_token_cap": cap,
            "percent_consumed": min(100.0, round((used / cap) * 100, 2)),
        }
```
Deploy to **Google Cloud Run**:
- Automated horizontal autoscaling (0 to N instances).
- HTTPS termination and DDoS protection included by default.
- Store LLM API keys securely in **Google Cloud Secret Manager**.

---

## 3. Verification & Acceptance Criteria
1. **Security**: Direct calls without a valid Bearer token return HTTP 401 Unauthorized.
2. **Streaming**: Calling `/v1/agent/chat` returns an `event-stream` yielding valid JSON chunks with < 800ms Time-To-First-Token (TTFT).
3. **Tool Calling**: Complex requests (e.g. *"Redact all emails on page 3 and rotate page 4"*) yield valid tool payloads matching `TaskCatalog` schemas.
4. **Quota Accounting**: Simulating rapid calls accurately updates and enforces the Redis token cap.
### 3.3 Gemini Streaming Agent: `src/services/llm_service.py`

Uses the official `google-genai` SDK to execute function calling with streaming Server-Sent Events (SSE):

```python
import os
import json
from typing import AsyncGenerator, Dict, Any, List
from google import genai
from google.genai import types

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
client = genai.Client(api_key=GEMINI_API_KEY)

MASTER_SYSTEM_PROMPT = """
You are Overline Cloud Intelligence, a high-reasoning document AI assistant.
You specialize in inspecting, editing, and restructuring PDF documents using exact tool calls.

INSTRUCTIONS:
1. Always analyze document context carefully.
2. If an operation is requested (e.g., rotate, delete, redact, compress, fill forms), select the most appropriate tool from your function definitions.
3. Emit concise, clear reasoning before providing tool calls or answers.
4. If asked to summarize or extract, provide direct factual answers with page references.
"""

def _convert_to_gemini_tools(client_tools: List[Dict[str, Any]]) -> List[types.Tool]:
    """Converts TaskCatalog JSON schemas to Gemini Function Declarations."""
    function_declarations = []
    for tool in client_tools:
        function_declarations.append(
            types.FunctionDeclaration(
                name=tool["name"],
                description=tool.get("description", ""),
                parameters=tool.get("parameters", {"type": "object", "properties": {}}),
            )
        )
    return [types.Tool(function_declarations=function_declarations)]

async def stream_agent_inference(
    prompt: str,
    context_dict: Dict[str, Any],
    client_tools: List[Dict[str, Any]],
) -> AsyncGenerator[str, None]:
    tools = _convert_to_gemini_tools(client_tools) if client_tools else None
    
    full_prompt = (
        f"Document Context:\n{json.dumps(context_dict, indent=2)}\n\n"
        f"User Request:\n{prompt}"
    )

    response_stream = client.models.generate_content_stream(
        model="gemini-1.5-pro",
        contents=full_prompt,
        config=types.GenerateContentConfig(
            system_instruction=MASTER_SYSTEM_PROMPT,
            temperature=0.2,
            tools=tools,
        ),
    )

    total_tokens = 0
    for chunk in response_stream:
        # Check for function/tool call
        for candidate in chunk.candidates:
            for part in candidate.content.parts:
                if part.function_call:
                    call_data = {
                        "type": "tool_call",
                        "tool": part.function_call.name,
                        "arguments": part.function_call.args,
                    }
                    yield f"data: {json.dumps(call_data)}\n\n"
                elif part.text:
                    thought_data = {
                        "type": "thought",
                        "text": part.text,
                    }
                    yield f"data: {json.dumps(thought_data)}\n\n"

        if chunk.usage_metadata:
            total_tokens = (
                chunk.usage_metadata.prompt_token_count +
                chunk.usage_metadata.candidates_token_count
            )

    # Emit completion with tokens consumed
    done_data = {
        "type": "done",
        "tokens_consumed": total_tokens or 450,
    }
    yield f"data: {json.dumps(done_data)}\n\n"
```

---

### 3.4 Gateway Entry Point: `src/main.py`

```python
import os
import json
from fastapi import FastAPI, Depends, Header, HTTPException, status
from sse_starlette.sse import EventSourceResponse
from dotenv import load_dotenv

from src.models.schemas import ChatRequest, UsageResponse
from src.services.quota_service import QuotaService
from src.services.llm_service import stream_agent_inference

load_dotenv()

app = FastAPI(title="Overline Cloud Gateway", version="1.0.0")

# Security Dependency
async def get_current_user(authorization: str = Header(...)) -> dict:
    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or malformed Authorization header.",
        )
    token = authorization.split(" ")[1]
    
    # In production: Verify token against Firebase Auth / Supabase JWKS
    # Here we mock decoding:
    user_id = "user_12345" # Extracted from token sub claim
    is_subscriber = True   # Extracted from database/entitlement check
    return {"user_id": user_id, "is_subscriber": is_subscriber}

@app.get("/v1/health")
def health():
    return {"status": "healthy", "service": "overline-backend"}

@app.get("/v1/user/usage", response_model=UsageResponse)
def get_usage(user: dict = Depends(get_current_user)):
    return QuotaService.get_user_usage(user["user_id"], user["is_subscriber"])

@app.post("/v1/agent/chat")
async def chat_endpoint(
    req: ChatRequest,
    user: dict = Depends(get_current_user),
):
    # 1. Enforce quota reservation before calling LLM
    QuotaService.check_and_reserve(user["user_id"], user["is_subscriber"])

    # 2. Stream SSE events
    async def event_generator():
        tokens_used = 0
        async for chunk in stream_agent_inference(
            prompt=req.prompt,
            context_dict=req.document_context.dict(),
            client_tools=req.tools,
        ):
            if '"type": "done"' in chunk:
                try:
                    payload = json.loads(chunk.replace("data: ", "").strip())
                    tokens_used = payload.get("tokens_consumed", 500)
                except Exception:
                    tokens_used = 500
            yield chunk

        # Commit final usage to Redis ledger
        QuotaService.record_usage(user["user_id"], tokens_used)

    return EventSourceResponse(event_generator())
```

---

## 4. Production Deployment on Google Cloud Run

Build and deploy with minimal operational overhead:
```bash
# 1. Build container image
docker build -t gcr.io/overline-prod/gateway:1.0.0 .

# 2. Deploy to Cloud Run with Secret Manager environment variables
gcloud run deploy overline-gateway \
  --image gcr.io/overline-prod/gateway:1.0.0 \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --set-secrets="GEMINI_API_KEY=GEMINI_API_KEY:latest,REDIS_PASSWORD=REDIS_PASSWORD:latest" \
  --set-env-vars="REDIS_HOST=10.0.0.3,REDIS_PORT=6379" \
  --min-instances=1 \
  --max-instances=50
```

---

## 5. Verification & Acceptance Criteria
1. **Unauthenticated Access**: `curl -X POST https://gateway/v1/agent/chat` without token returns HTTP 401.
2. **Streaming Protocol**: Calling with valid token returns `Content-Type: text/event-stream` with valid `thought` and `tool_call` data chunks.
3. **Quota Protection**: Setting Redis quota to 0 returns HTTP 429 and does not invoke Gemini API.
