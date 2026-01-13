defmodule Mix.Tasks.GoogleQuestions do
  @moduledoc """
  Fetch Google Questions and Answers from DataForSEO API and save to JSON file.

  Retrieves questions and answers posted on a Google Business Profile.

  ## Usage

      mix google_questions [options]

  ## Options

    * `--keyword`, `-k` - Business name to search (requires --location)
    * `--cid`, `-c` - Google Customer ID (preferred, from business_listings)
    * `--place-id`, `-p` - Google Place ID
    * `--location`, `-l` - Location for keyword search (name, code, or coordinate)
    * `--depth`, `-n` - Number of questions to fetch (default: 20, max: 700)
    * `--language`, `-g` - Language code (default: en)
    * `--output`, `-o` - Output JSON file (default: google_questions.json)

  ## Examples

      # Fetch questions using CID from business listing
      mix google_questions --cid "10179360708466590899" --depth 50

      # Fetch questions by business name
      mix google_questions -k "The Last Bookstore" -l "Los Angeles,California,United States" -n 100

      # Fetch questions using place_id
      mix google_questions --place-id "ChIJOwg_06VPwokRYv534QaPC8g" --depth 30 -o bookstore_qa.json

  ## Billing Note

  Your DataForSEO account will be billed for every 20 questions fetched.
  The maximum number of answers returned per question is 5.
  """

  use Mix.Task

  alias DataForSEO.Schemas.GoogleQuestionsResult

  @shortdoc "Fetch Google Questions and Answers from DataForSEO and save to JSON"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _remaining, invalid} =
      OptionParser.parse(args,
        switches: [
          keyword: :string,
          cid: :string,
          place_id: :string,
          location: :string,
          depth: :integer,
          language: :string,
          output: :string
        ],
        aliases: [
          k: :keyword,
          c: :cid,
          p: :place_id,
          l: :location,
          n: :depth,
          g: :language,
          o: :output
        ]
      )

    if length(invalid) > 0 do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    task_params = build_task_params(opts)
    validate_params!(task_params)

    display_search_info(task_params, opts)

    start_time = System.monotonic_time(:millisecond)
    result = execute_search(task_params, start_time)
    elapsed_ms = System.monotonic_time(:millisecond) - start_time

    output_path = opts[:output] || "google_questions.json"
    save_results(result, task_params, output_path, elapsed_ms)
    display_summary(result, output_path, elapsed_ms)
  end

  @doc """
  Builds task parameters from CLI options.
  """
  @spec build_task_params(keyword()) :: map()
  def build_task_params(opts) do
    params =
      %{}
      |> maybe_put(:keyword, opts[:keyword])
      |> maybe_put(:cid, opts[:cid])
      |> maybe_put(:place_id, opts[:place_id])
      |> maybe_put(:depth, opts[:depth])
      |> maybe_put(:language_code, opts[:language])

    # Add location if provided, or use default for CID/place_id
    cond do
      opts[:location] ->
        Map.put(params, :location_name, opts[:location])

      opts[:cid] || opts[:place_id] ->
        # CID and place_id still require a location parameter per DataForSEO API
        # Use a default location code that covers United States
        Map.put(params, :location_code, 2840)

      true ->
        params
    end
  end

  @doc """
  Executes the questions search and waits for results.
  """
  @spec execute_search(map(), integer()) :: GoogleQuestionsResult.t()
  def execute_search(task_params, start_time) do
    Mix.shell().info("🔍 Fetching Google Questions and Answers...")

    ref = make_ref()
    parent = self()
    callback = fn result -> send(parent, {ref, result}) end

    case DataForSEO.Supervisor.start_task(
           DataForSEO.Tasks.GoogleQuestions,
           task_params,
           callback: callback
         ) do
      {:ok, pid} ->
        Mix.shell().info("⏳ Task created (PID: #{inspect(pid)}), polling for results...")
        wait_for_results(ref, pid, start_time)

      {:error, reason} ->
        Mix.shell().error("✗ Failed to start task: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  @doc """
  Saves questions and answers results to JSON file.
  """
  @spec save_results(GoogleQuestionsResult.t(), map(), String.t(), integer()) :: :ok
  def save_results(result, search_params, output_path, elapsed_ms) do
    Mix.shell().info("💾 Saving to #{output_path}...")

    data = %{
      keyword: result.metadata.keyword,
      cid: result.metadata.cid,
      location_code: result.metadata.location_code,
      language_code: result.metadata.language_code,
      total_questions: GoogleQuestionsResult.total_question_count(result),
      answered_questions: GoogleQuestionsResult.answered_question_count(result),
      unanswered_questions: GoogleQuestionsResult.unanswered_question_count(result),
      fetched_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      elapsed_ms: elapsed_ms,
      search_params: search_params,
      check_url: result.metadata.check_url,
      questions_with_answers: Enum.map(result.questions_with_answers, &struct_to_map/1),
      questions_without_answers: Enum.map(result.questions_without_answers, &struct_to_map/1)
    }

    json = Jason.encode!(data, pretty: true)
    File.write!(output_path, json)

    total = GoogleQuestionsResult.total_question_count(result)
    Mix.shell().info("✓ Successfully saved #{total} questions")
  end

  # Private functions

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp validate_params!(params) do
    has_identifier = params[:keyword] || params[:cid] || params[:place_id]

    unless has_identifier do
      Mix.raise("At least one business identifier required (--keyword, --cid, or --place-id)")
    end

    # Keyword requires explicit location
    if params[:keyword] && !params[:location_name] && !params[:location_code] &&
         !params[:location_coordinate] do
      Mix.raise("--location required when using --keyword")
    end

    :ok
  end

  defp display_search_info(params, opts) do
    Mix.shell().info("\n=== Search Parameters ===")

    display_identifier(params)
    display_location(params)

    depth = opts[:depth] || 20
    Mix.shell().info("Depth: #{depth}")
    Mix.shell().info("Language: #{params[:language_code] || "en"}")

    Mix.shell().info("========================\n")
  end

  defp display_identifier(params) do
    cond do
      params[:cid] -> Mix.shell().info("CID: #{params[:cid]}")
      params[:place_id] -> Mix.shell().info("Place ID: #{params[:place_id]}")
      params[:keyword] -> Mix.shell().info("Keyword: #{params[:keyword]}")
    end
  end

  defp display_location(params) do
    cond do
      params[:location_name] ->
        Mix.shell().info("Location: #{params[:location_name]}")

      params[:location_code] ->
        Mix.shell().info("Location Code: #{params[:location_code]}")

      params[:location_coordinate] ->
        Mix.shell().info("Location Coordinate: #{params[:location_coordinate]}")

      true ->
        nil
    end
  end

  defp wait_for_results(ref, pid, start_time) do
    receive do
      {^ref, {:ok, result}} ->
        result

      {^ref, {:error, reason}} ->
        Mix.shell().error("✗ Task failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    after
      5_000 ->
        elapsed_s = div(System.monotonic_time(:millisecond) - start_time, 1000)

        status =
          if Process.alive?(pid) do
            case DataForSEO.TaskManager.get_status(pid) do
              {:ok, state} -> state.status
              _ -> :unknown
            end
          else
            :dead
          end

        Mix.shell().info("⏱️  Elapsed: #{elapsed_s}s, Status: #{status}...")
        wait_for_results(ref, pid, start_time)
    end
  end

  defp display_summary(result, output_path, elapsed_ms) do
    Mix.shell().info("\n=== Summary ===")
    Mix.shell().info("Business: #{result.metadata.keyword}")

    if result.metadata.cid do
      Mix.shell().info("CID: #{result.metadata.cid}")
    end

    total = GoogleQuestionsResult.total_question_count(result)
    answered = GoogleQuestionsResult.answered_question_count(result)
    unanswered = GoogleQuestionsResult.unanswered_question_count(result)

    Mix.shell().info("Total questions: #{total}")
    Mix.shell().info("  • With answers: #{answered}")
    Mix.shell().info("  • Without answers: #{unanswered}")
    Mix.shell().info("Time elapsed: #{format_elapsed(elapsed_ms)}")
    Mix.shell().info("Output file: #{output_path}")

    # Show recent questions summary
    if total > 0 do
      display_recent_questions(result)
    end

    Mix.shell().info("===============\n")
  end

  defp display_recent_questions(result) do
    display_answered_questions(result.questions_with_answers)
    display_unanswered_questions(result.questions_without_answers)
  end

  defp display_answered_questions(questions) do
    Mix.shell().info("\n=== Recent Questions ===")

    questions
    |> Enum.take(3)
    |> Enum.each(&display_answered_question/1)
  end

  defp display_answered_question(question) do
    text = truncate_text(question.question_text, 80)
    answer_count = length(question.answers)

    Mix.shell().info("  ❓ #{text}")

    Mix.shell().info(
      "     #{answer_count} answer(s) - by #{question.profile_name || "Anonymous"}"
    )

    if answer_count > 0 do
      display_first_answer(hd(question.answers))
    end
  end

  defp display_first_answer(answer) do
    answer_text = truncate_text(answer.answer_text, 60)
    Mix.shell().info("     💬 \"#{answer_text}\"")
  end

  defp display_unanswered_questions([]), do: :ok

  defp display_unanswered_questions(questions) do
    Mix.shell().info("\n=== Recent Unanswered Questions ===")

    questions
    |> Enum.take(2)
    |> Enum.each(&display_unanswered_question/1)
  end

  defp display_unanswered_question(question) do
    text = truncate_text(question.question_text, 80)
    Mix.shell().info("  ❓ #{text}")
    Mix.shell().info("     No answers yet - by #{question.profile_name || "Anonymous"}")
  end

  defp truncate_text(nil, _max_length), do: ""

  defp truncate_text(text, max_length) do
    if String.length(text) > max_length do
      "#{String.slice(text, 0..max_length)}..."
    else
      text
    end
  end

  defp format_elapsed(ms) when ms < 1_000, do: "#{ms}ms"
  defp format_elapsed(ms), do: "#{Float.round(ms / 1000, 1)}s"

  defp struct_to_map(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Enum.map(fn {k, v} -> {k, struct_to_map(v)} end)
    |> Map.new()
  end

  defp struct_to_map(value), do: value
end
