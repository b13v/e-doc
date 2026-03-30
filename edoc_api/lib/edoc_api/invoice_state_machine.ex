defmodule EdocApi.InvoiceStateMachine do
  @moduledoc """
  State machine for invoice status transitions.

  Enforces valid status transitions and prevents invalid state changes.
  This ensures business rules are enforced consistently across the application.

  ## Transitions

      draft -> issued, void
      issued -> paid, void
      paid -> void
      void -> (terminal state, no transitions out)

  ## Examples

      iex> InvoiceStateMachine.can_transition?("draft", "issued")
      true

      iex> InvoiceStateMachine.can_transition?("issued", "draft")
      false

      iex> InvoiceStateMachine.transition(%Invoice{status: "draft"}, "issued")
      {:ok, "issued"}

      iex> InvoiceStateMachine.transition(%Invoice{status: "issued"}, "draft")
      {:error, :invalid_transition, %{from: "issued", to: "draft", reason: "cannot return to draft"}}

  """

  alias EdocApi.InvoiceStatus

  # Define allowed transitions from each state
  @transitions %{
    "draft" => [:issued, :void],
    "issued" => [:paid, :void],
    "paid" => [:void],
    "void" => []
  }

  # Transition reasons for error messages
  @transition_reasons %{
    {"draft", "issued"} => :none,
    {"draft", "void"} => :none,
    {"issued", "paid"} => :none,
    {"issued", "void"} => :none,
    {"paid", "void"} => :none
  }

  @type invoice :: %{status: String.t()} | struct()
  @type status :: String.t()
  @type transition_result :: {:ok, status()} | {:error, :invalid_transition, map()}

  @doc """
  Checks if a transition from one status to another is allowed.

  ## Examples

      iex> InvoiceStateMachine.can_transition?("draft", "issued")
      true

      iex> InvoiceStateMachine.can_transition?("issued", "draft")
      false

      iex> InvoiceStateMachine.can_transition?("void", "issued")
      false

  """
  @spec can_transition?(status(), status()) :: boolean()
  def can_transition?(from_status, to_status) do
    case Map.get(@transitions, from_status) do
      nil -> false
      allowed -> to_status in allowed
    end
  end

  @doc """
  Validates and executes a status transition.

  Returns {:ok, new_status} if the transition is valid.
  Returns {:error, :invalid_transition, details} if invalid.

  ## Examples

      iex> InvoiceStateMachine.transition(%{status: "draft"}, "issued")
      {:ok, "issued"}

      iex> InvoiceStateMachine.transition(%{status: "issued"}, "draft")
      {:error, :invalid_transition, %{from: "issued", to: "draft", reason: "cannot return to draft"}}

  """
  @spec transition(invoice(), status()) :: transition_result()
  def transition(%{status: from_status}, to_status) do
    if can_transition?(from_status, to_status) do
      {:ok, to_status}
    else
      reason = get_transition_reason(from_status, to_status)
      {:error, :invalid_transition, %{from: from_status, to: to_status, reason: reason}}
    end
  end

  @doc """
  Returns all allowed next statuses for a given current status.

  ## Examples

      iex> InvoiceStateMachine.allowed_transitions("draft")
      [:issued, :void]

      iex> InvoiceStateMachine.allowed_transitions("void")
      []

  """
  @spec allowed_transitions(status()) :: [status()]
  def allowed_transitions(current_status) do
    Map.get(@transitions, current_status, [])
  end

  @doc """
  Checks if an invoice is in a terminal state (no transitions allowed).

  ## Examples

      iex> InvoiceStateMachine.terminal_state?("void")
      true

      iex> InvoiceStateMachine.terminal_state?("draft")
      false

  """
  @spec terminal_state?(status()) :: boolean()
  def terminal_state?(status) do
    allowed_transitions(status) == []
  end

  @doc """
  Returns a human-readable reason why a transition is not allowed.

  ## Examples

      iex> InvoiceStateMachine.get_transition_reason("issued", "draft")
      "cannot return to draft"

      iex> InvoiceStateMachine.get_transition_reason("void", "issued")
      "void is a terminal state"

  """
  @spec get_transition_reason(status(), status()) :: String.t()
  def get_transition_reason(from_status, to_status) do
    cond do
      terminal_state?(from_status) ->
        "#{from_status} is a terminal state"

      from_status == to_status ->
        "already in #{from_status} status"

      not InvoiceStatus.valid?(to_status) ->
        "#{to_status} is not a valid status"

      true ->
        default_transition_reason(from_status, to_status)
    end
  end

  # Private helper for default transition reasons
  defp default_transition_reason(from_status, to_status) do
    case Map.get(@transition_reasons, {from_status, to_status}) do
      :none -> "cannot transition from #{from_status} to #{to_status}"
      reason -> reason
    end
  end

  @doc """
  Returns all defined transitions (useful for testing/documentation).

  ## Examples

      iex> InvoiceStateMachine.all_transitions()
      %{
        "draft" => [:issued, :void],
        "issued" => [:paid, :void],
        "paid" => [:void],
        "void" => []
      }

  """
  @spec all_transitions() :: map()
  def all_transitions, do: @transitions

  @doc """
  Returns all valid statuses (delegates to InvoiceStatus).

  ## Examples

      iex> InvoiceStateMachine.all_statuses()
      ["draft", "issued", "paid", "void"]

  """
  @spec all_statuses() :: [status()]
  def all_statuses, do: InvoiceStatus.all()
end
