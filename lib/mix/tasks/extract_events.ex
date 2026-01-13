defmodule Mix.Tasks.ExtractEvents do
  @moduledoc """
  Extracts structured event data from event listings.

  ## Usage

      # Extract from a markdown or HTML file
      mix extract_events events.md

      # Extract with full descriptions
      mix extract_events events.md --descriptions

      # Output to specific file
      mix extract_events events.md --output enhanced-events.json

      # Skip validation
      mix extract_events events.md --no-validate

  ## Options

    * `--descriptions` - Include full event descriptions (default: true)
    * `--output` - Output file path (default: events-extracted.json)
    * `--validate` - Validate extracted data (default: true)
    * `--enhance` - Add computed fields (default: true)
  """

  use Mix.Task
  alias Mulberry.Extractors.EventsExtractor

  @shortdoc "Extract structured event data from event listings"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, [file_path], _} =
      OptionParser.parse(args,
        switches: [
          descriptions: :boolean,
          output: :string,
          validate: :boolean,
          enhance: :boolean
        ],
        aliases: [
          d: :descriptions,
          o: :output,
          v: :validate,
          e: :enhance
        ]
      )

    # Set defaults
    include_descriptions = Keyword.get(opts, :descriptions, true)
    output_path = Keyword.get(opts, :output, "events-extracted.json")
    validate = Keyword.get(opts, :validate, true)
    enhance = Keyword.get(opts, :enhance, true)

    case extract_events_from_file(file_path, include_descriptions, validate, enhance) do
      {:ok, events} ->
        write_output(events, output_path)
        Mix.shell().info("✓ Successfully extracted #{length(events)} events to #{output_path}")

        if validate do
          Mix.shell().info("✓ All events validated successfully")
        end

        # Print summary
        print_summary(events)

      {:error, reason} ->
        Mix.shell().error("✗ Extraction failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp extract_events_from_file(file_path, include_descriptions, validate, enhance) do
    with {:ok, content} <- File.read(file_path),
         {:ok, events} <-
           EventsExtractor.extract(content,
             include_descriptions: include_descriptions
           ),
         {:ok, validated_events} <- maybe_validate(events, validate),
         enhanced_events <- maybe_enhance(validated_events, enhance) do
      {:ok, enhanced_events}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_validate(events, true) do
    EventsExtractor.validate_events(events)
  end

  defp maybe_validate(events, false), do: {:ok, events}

  defp maybe_enhance(events, true) do
    EventsExtractor.enhance_events(events)
  end

  defp maybe_enhance(events, false), do: events

  defp write_output(events, output_path) do
    json = Jason.encode!(events, pretty: true)
    File.write!(output_path, json)
  end

  defp print_summary(events) do
    Mix.shell().info("\n📊 Extraction Summary:")
    Mix.shell().info("  Total events: #{length(events)}")

    # Count by audience
    audiences =
      events
      |> Enum.flat_map(&Map.get(&1, "audience", []))
      |> Enum.frequencies()

    Mix.shell().info("\n  Events by audience:")

    Enum.each(audiences, fn {audience, count} ->
      Mix.shell().info("    • #{audience}: #{count}")
    end)

    # Count by category
    categories =
      events
      |> Enum.flat_map(&Map.get(&1, "categories", []))
      |> Enum.frequencies()

    Mix.shell().info("\n  Events by category:")

    Enum.each(categories, fn {category, count} ->
      Mix.shell().info("    • #{category}: #{count}")
    end)

    # Count events with registration
    registration_count =
      events
      |> Enum.count(&(get_in(&1, ["registration", "required"]) == true))

    if registration_count > 0 do
      Mix.shell().info("\n  Events requiring registration: #{registration_count}")
    end

    # Count recurring events
    recurring_count =
      events
      |> Enum.count(&(get_in(&1, ["date", "isRecurring"]) == true))

    if recurring_count > 0 do
      Mix.shell().info("  Recurring events: #{recurring_count}")
    end
  end
end
