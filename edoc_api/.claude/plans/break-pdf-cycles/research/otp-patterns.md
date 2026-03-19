# OTP Patterns Research: Async PDF Generation

## Recommendation: Task.Supervisor + Database Polling

### NOT Recommended: Oban (initially)

Oban is overkill for current needs. Adds dependency complexity without clear benefit yet.

### Recommended Pattern

```elixir
# Add to supervision tree
{Task.Supervisor, name: EdocApi.PdfGenerationSupervisor}

# Async PDF generation
def generate_async(html, opts \\ []) do
  Task.Supervisor.async_nolink(
    EdocApi.PdfGenerationSupervisor,
    fn -> Pdf.html_to_pdf(html, opts) end
  )
end

# With status tracking in database
alter table(:contracts) do
  add :pdf_generation_status, :string, default: "pending"
  add :pdf_storage_path, :string
end
```

### Implementation Overview

1. **Task.Supervisor** - Supervised one-off async work (fault isolation)
2. **Database** - Persist generation status
3. **PubSub** - Notify clients on completion (optional)

### Why NOT GenServer

- PDF generation is stateless computation
- No state to manage between operations
- Each PDF is independent
- GenServer adds unnecessary complexity

### User Experience

**Before:** User waits 2-10 seconds with blocking HTTP request

**After:**
- User gets immediate "generating" response
- Can poll for status
- PDF available immediately on subsequent requests
- Better scalability under concurrent load

### Retry Strategy

```elixir
defp perform_generation(document, type, attempt \\ 1) do
  case Pdf.generate_async(html, opts) do
    {:ok, task} ->
      case Task.yield(task, 60_000) do
        {:ok, {:ok, pdf_binary}} -> store_pdf(document, pdf_binary)
        {:ok, {:error, _}} when attempt < 3 ->
          Process.sleep(:timer.seconds(attempt * 2))
          perform_generation(document, type, attempt + 1)
        _ -> handle_failure(document, :timeout)
      end
  end
end
```
