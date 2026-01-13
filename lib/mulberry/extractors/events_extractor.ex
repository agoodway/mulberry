defmodule Mulberry.Extractors.EventsExtractor do
  @moduledoc """
  Extracts structured event data from event listings with comprehensive detail.

  This extractor captures:
  - Basic event information (title, date, time, location)
  - Rich content (descriptions, images)
  - Registration details (requirements, availability)
  - Recurrence patterns
  - Event metadata (URLs, IDs)
  """

  alias Mulberry.Text
  require Logger

  @doc """
  Extracts comprehensive event data from event content.

  ## Options
    - `:llm` - The LLM to use for extraction (defaults to OpenAI)
    - `:include_descriptions` - Whether to extract full descriptions (default: true)
    - `:normalize_audiences` - Whether to normalize audience names (default: true)
  """
  @spec extract(String.t(), keyword()) :: {:ok, list(map())} | {:error, term()}
  def extract(content, opts \\ []) do
    include_descriptions = Keyword.get(opts, :include_descriptions, true)

    schema = build_extraction_schema(include_descriptions)
    system_message = build_system_message()

    # Merge the schema and system message into opts
    extraction_opts =
      opts
      |> Keyword.put(:schema, schema)
      |> Keyword.put(:system_message, system_message)

    case Text.extract(content, extraction_opts) do
      {:ok, events} when is_list(events) ->
        {:ok, events}

      {:ok, event} when is_map(event) ->
        {:ok, [event]}

      {:error, reason} ->
        Logger.error("Failed to extract events: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_extraction_schema(include_descriptions) do
    description_property =
      if include_descriptions do
        %{type: "string", description: "Full event description text"}
      else
        nil
      end

    base_properties = %{
      title: %{type: "string", description: "Event name"},
      eventId: %{type: "string", description: "Unique identifier from URL if available"},
      url: %{type: "string", description: "Direct link to event details page"},
      eventType: %{
        type: "string",
        enum: ["in-person", "virtual", "hybrid"],
        description: "Type of event"
      },
      date: %{
        type: "object",
        properties: %{
          startDate: %{
            type: "string",
            format: "date",
            description: "Start date in YYYY-MM-DD format"
          },
          endDate: %{
            type: "string",
            format: "date",
            description: "End date if different from start"
          },
          isRecurring: %{type: "boolean", description: "Whether event repeats"},
          recurrencePattern: %{type: "string", description: "Description of recurrence pattern"}
        },
        required: ["startDate"]
      },
      time: %{
        type: "object",
        properties: %{
          startTime: %{type: "string", description: "Start time (e.g., '2:00 PM')"},
          endTime: %{type: "string", description: "End time"},
          timezone: %{type: "string", description: "Timezone if specified"}
        },
        required: ["startTime"]
      },
      location: %{
        type: "object",
        properties: %{
          venueName: %{type: "string", description: "Main venue name"},
          roomName: %{type: "string", description: "Specific room or area"},
          address: %{type: "string", description: "Full address if available"}
        },
        required: ["venueName"]
      },
      audience: %{
        type: "array",
        items: %{type: "string"},
        description: "Target audiences (normalized to lowercase with hyphens)"
      },
      categories: %{
        type: "array",
        items: %{type: "string"},
        description: "Event categories"
      },
      registration: %{
        type: "object",
        properties: %{
          required: %{type: "boolean", description: "Whether registration is required"},
          registrationType: %{type: "string", description: "Type of registration"},
          seatsAvailable: %{type: "integer", description: "Number of seats left"},
          registrationUrl: %{type: "string", description: "Link to register"}
        }
      },
      images: %{
        type: "array",
        items: %{type: "string"},
        description: "URLs of associated images"
      },
      additionalNotes: %{type: "string", description: "Any special notes or requirements"}
    }

    # Add description if requested
    properties =
      if description_property do
        Map.put(base_properties, :description, description_property)
      else
        base_properties
      end

    %{
      type: "object",
      properties: properties,
      required: ["title", "date", "time", "location", "eventType"]
    }
  end

  defp build_system_message do
    """
    You are an expert at extracting structured event data from various formats.

    Important extraction rules:
    1. Extract ALL events found in the content
    2. Preserve exact times and dates as shown
    3. Normalize audience names to lowercase with hyphens (e.g., "All Ages" -> "all-ages")
    4. Include all audience types for events with multiple audiences
    5. Capture recurring event indicators (look for "Show more dates" or similar)
    6. Extract registration requirements and seat availability when present
    7. Extract event IDs from URLs when available (e.g., /event/13101180 -> eventId: "13101180")
    8. Ensure dates are in YYYY-MM-DD format
    9. Return multiple events if multiple are found in the content
    """
  end

  @doc """
  Validates extracted event data for completeness and accuracy.
  """
  @spec validate_events(list(map())) :: {:ok, list(map())} | {:error, list(String.t())}
  def validate_events(events) when is_list(events) do
    errors =
      events
      |> Enum.with_index()
      |> Enum.flat_map(fn {event, index} ->
        validate_event(event, index)
      end)

    if Enum.empty?(errors) do
      {:ok, events}
    else
      {:error, errors}
    end
  end

  defp validate_event(event, index) do
    required_fields = ["title", "date", "time", "location", "eventType"]

    missing_fields =
      required_fields
      |> Enum.reject(&Map.has_key?(event, &1))

    errors =
      case missing_fields do
        [] -> []
        fields -> ["Event #{index}: Missing required fields: #{Enum.join(fields, ", ")}"]
      end

    # Validate date format
    errors =
      case Map.get(event, "date") do
        %{"startDate" => date} ->
          if valid_date_format?(date) do
            errors
          else
            ["Event #{index}: Invalid date format: #{date}" | errors]
          end

        _ ->
          errors
      end

    errors
  end

  defp valid_date_format?(date) do
    case Date.from_iso8601(date) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Enhances extracted events with additional computed fields.
  """
  @spec enhance_events(list(map())) :: list(map())
  def enhance_events(events) do
    events
    |> Enum.map(&enhance_event/1)
  end

  defp enhance_event(event) do
    event
    |> add_duration()
    |> add_formatted_datetime()
    |> add_audience_count()
  end

  defp add_duration(event) do
    case event do
      %{"time" => %{"startTime" => start_time, "endTime" => end_time}} ->
        duration = calculate_duration(start_time, end_time)
        put_in(event, ["time", "duration"], duration)

      _ ->
        event
    end
  end

  defp calculate_duration(start_time, end_time) do
    # Simple duration calculation - could be enhanced
    "#{start_time} - #{end_time}"
  end

  defp add_formatted_datetime(event) do
    case event do
      %{"date" => %{"startDate" => date}, "time" => %{"startTime" => time}} ->
        Map.put(event, "formattedDateTime", "#{date} at #{time}")

      _ ->
        event
    end
  end

  defp add_audience_count(event) do
    case Map.get(event, "audience") do
      audiences when is_list(audiences) ->
        Map.put(event, "audienceCount", length(audiences))

      _ ->
        event
    end
  end
end
