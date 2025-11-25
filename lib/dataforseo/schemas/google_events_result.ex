defmodule DataForSEO.Schemas.GoogleEventsResult do
  @moduledoc """
  Schema for the complete Google Events search result from DataForSEO API.

  Contains a list of events and metadata about the search.
  """

  alias DataForSEO.Schemas.GoogleEvent

  @type t :: %__MODULE__{
          events: [GoogleEvent.t()],
          metadata: metadata()
        }

  @type metadata :: %{
          total_count: integer() | nil,
          items_count: integer() | nil,
          keyword: String.t() | nil,
          location: String.t() | nil,
          language_code: String.t() | nil,
          check_url: String.t() | nil,
          datetime: String.t() | nil
        }

  defstruct [
    :events,
    :metadata
  ]

  @doc """
  Creates a new GoogleEventsResult struct from a map of attributes.

  Converts event maps to GoogleEvent structs automatically.
  """
  @spec new(map()) :: t()
  def new(%{events: events, metadata: metadata}) when is_list(events) do
    %__MODULE__{
      events: Enum.map(events, &GoogleEvent.new/1),
      metadata: metadata
    }
  end

  def new(%{} = attrs) do
    # Handle case where events might be nil
    events = Map.get(attrs, :events, [])
    metadata = Map.get(attrs, :metadata, %{})

    new(%{events: events, metadata: metadata})
  end

  @doc """
  Returns the count of events in the result.
  """
  @spec event_count(t()) :: non_neg_integer()
  def event_count(%__MODULE__{events: events}) do
    length(events)
  end

  @doc """
  Checks if the result contains any events.
  """
  @spec has_events?(t()) :: boolean()
  def has_events?(%__MODULE__{events: events}) do
    events != []
  end

  @doc """
  Gets events filtered by a specific date.
  """
  @spec events_by_date(t(), String.t()) :: [GoogleEvent.t()]
  def events_by_date(%__MODULE__{events: events}, date) do
    Enum.filter(events, fn event -> event.date == date end)
  end

  @doc """
  Gets events that have ticket URLs available.
  """
  @spec events_with_tickets(t()) :: [GoogleEvent.t()]
  def events_with_tickets(%__MODULE__{events: events}) do
    Enum.filter(events, fn event -> event.tickets_url != nil end)
  end

  @doc """
  Gets events filtered by start datetime.

  Accepts datetime strings in ISO 8601 format (e.g., "2024-11-07T20:00:00").
  """
  @spec events_by_start_datetime(t(), String.t()) :: [GoogleEvent.t()]
  def events_by_start_datetime(%__MODULE__{events: events}, start_datetime) do
    Enum.filter(events, fn event ->
      event.event_dates && event.event_dates.start_datetime == start_datetime
    end)
  end

  @doc """
  Gets events happening within a date range.

  Accepts datetime strings in ISO 8601 format.
  """
  @spec events_in_range(t(), String.t(), String.t()) :: [GoogleEvent.t()]
  def events_in_range(%__MODULE__{events: events}, start_datetime, end_datetime) do
    Enum.filter(events, fn event ->
      if event.event_dates && event.event_dates.start_datetime do
        event.event_dates.start_datetime >= start_datetime &&
          event.event_dates.start_datetime <= end_datetime
      else
        false
      end
    end)
  end

  @doc """
  Gets all unique ticket vendors across all events.

  Returns a list of unique domains where tickets are available.
  """
  @spec ticket_vendors(t()) :: [String.t()]
  def ticket_vendors(%__MODULE__{events: events}) do
    events
    |> Enum.flat_map(fn event ->
      (event.information_and_tickets || [])
      |> Enum.map(& &1.domain)
      |> Enum.reject(&is_nil/1)
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Gets events that have tickets available from a specific vendor.

  ## Examples

      events_by_vendor(result, "www.stubhub.com")
  """
  @spec events_by_vendor(t(), String.t()) :: [GoogleEvent.t()]
  def events_by_vendor(%__MODULE__{events: events}, vendor_domain) do
    Enum.filter(events, fn event ->
      event.information_and_tickets &&
        Enum.any?(event.information_and_tickets, fn ticket ->
          ticket.domain == vendor_domain
        end)
    end)
  end

  @doc """
  Gets all ticket URLs for a specific event.

  Returns a list of maps with vendor information and URLs.
  """
  @spec ticket_urls_for_event(GoogleEvent.t()) :: [map()]
  def ticket_urls_for_event(event) do
    (event.information_and_tickets || [])
    |> Enum.map(fn ticket ->
      %{
        vendor: ticket.title || ticket.domain,
        url: ticket.url,
        domain: ticket.domain
      }
    end)
  end
end
