# Example: Document Summarization with Advanced Strategies
# 
# This example demonstrates how document summarization now uses
# the SummarizeDocumentChain internally with different strategies.

# Ensure you have set the OPENAI_API_KEY environment variable
unless System.get_env("OPENAI_API_KEY") do
  IO.puts("Please set the OPENAI_API_KEY environment variable")
  System.halt(1)
end

alias Mulberry.Document
alias Mulberry.Document.WebPage
alias Mulberry.Text

# Example 1: Basic summarization (uses stuff strategy by default)
IO.puts("=== Example 1: Basic Summarization ===\n")

# Create a sample document
doc =
  WebPage.new(%{
    url: "https://example.com",
    markdown: """
    # Introduction to Elixir

    Elixir is a dynamic, functional language designed for building maintainable 
    and scalable applications. It leverages the Erlang VM, known for running 
    low-latency, distributed and fault-tolerant systems.

    ## Key Features

    1. **Scalability** - All Elixir code runs inside lightweight threads of 
       execution (called processes) that are isolated and exchange information 
       via messages.

    2. **Fault-tolerance** - Elixir provides supervisors which describe how to 
       restart parts of your system when things go wrong.

    3. **Functional programming** - Elixir is a functional programming language 
       that promotes immutability and transformation of data.

    4. **Extensibility** - Elixir has been designed to be extensible, allowing 
       developers to naturally extend the language to particular domains.

    ## Getting Started

    To get started with Elixir, you'll need to install it on your system. 
    Visit elixir-lang.org for installation instructions.
    """
  })

# Basic summarization (uses stuff strategy internally)
{:ok, doc_with_summary} = Document.generate_summary(doc)
IO.puts("Summary: #{doc_with_summary.summary}\n")

# Example 2: Map-Reduce Strategy with Progress Tracking
IO.puts("\n=== Example 2: Map-Reduce with Progress Tracking ===\n")

# Create a longer document that will be chunked
long_doc =
  WebPage.new(%{
    url: "https://example.com/long",
    markdown: """
    # Comprehensive Guide to Elixir

    #{String.duplicate("This is a section about Elixir's features. " <> "It contains detailed information about the language, its ecosystem, " <> "and best practices for development. ",
    20)}

    ## Chapter 1: Getting Started

    #{String.duplicate("Learning Elixir starts with understanding its functional nature. " <> "The language promotes immutability and data transformation. ",
    15)}

    ## Chapter 2: OTP and Concurrency

    #{String.duplicate("OTP is a set of libraries and design principles for building " <> "distributed, fault-tolerant applications. ",
    15)}

    ## Chapter 3: Phoenix Framework

    #{String.duplicate("Phoenix is a productive web framework that does not compromise " <> "speed or maintainability. ",
    15)}
    """
  })

# Use map-reduce strategy with progress tracking
{:ok, summary} =
  Document.generate_summary(long_doc,
    strategy: :map_reduce,
    chunk_size: 500,
    on_progress: fn stage, info ->
      IO.puts("Progress - #{stage}: #{inspect(info)}")
    end
  )

IO.puts("\nFinal Summary: #{summary.summary}\n")

# Example 3: Refine Strategy
IO.puts("\n=== Example 3: Refine Strategy ===\n")

# Create a document with sequential information
sequential_doc =
  WebPage.new(%{
    url: "https://example.com/tutorial",
    markdown: """
    # Building a Chat Application

    ## Step 1: Project Setup
    First, create a new Phoenix project with LiveView support.
    Run `mix phx.new chat_app --live` to generate the project structure.

    ## Step 2: Database Schema
    Next, design the database schema for users and messages.
    Create migrations for the users and messages tables.

    ## Step 3: Authentication
    Implement user authentication using the phx.gen.auth generator.
    This provides a complete authentication system out of the box.

    ## Step 4: Real-time Features
    Use Phoenix Channels and LiveView to implement real-time messaging.
    Messages should appear instantly without page refresh.

    ## Step 5: Deployment
    Finally, deploy the application to a platform like Fly.io.
    Configure the production environment and set up the database.
    """
  })

{:ok, refined_summary} =
  Document.generate_summary(sequential_doc,
    strategy: :refine,
    chunk_overlap: 100,
    verbose: false
  )

IO.puts("Refined Summary: #{refined_summary.summary}\n")

# Example 4: Direct text summarization
IO.puts("\n=== Example 4: Direct Text Summarization ===\n")

text = """
The Phoenix Framework is a highly productive web framework for Elixir that 
implements the server-side Model View Controller (MVC) pattern. It provides 
high developer productivity while delivering high application performance. 
Phoenix leverages the Erlang VM ability to handle millions of connections 
alongside Elixir's beautiful syntax and productive tooling.
"""

# Summarize text directly with custom options
{:ok, text_summary} =
  Text.summarize(text,
    strategy: :stuff,
    temperature: 0.3,
    max_tokens: 100
  )

IO.puts("Text Summary: #{text_summary}\n")

# Example 5: Using different LLM providers
IO.puts("\n=== Example 5: Different LLM Providers ===\n")

# You can specify different providers if configured
# Add :anthropic, :google if you have API keys
providers = [:openai]

Enum.each(providers, fn provider ->
  IO.puts("Using provider: #{provider}")

  try do
    {:ok, summary} =
      Document.generate_summary(doc,
        provider: provider,
        strategy: :stuff
      )

    IO.puts("Summary: #{String.slice(summary.summary, 0, 100)}...\n")
  rescue
    e -> IO.puts("Error with #{provider}: #{Exception.message(e)}\n")
  end
end)

# Example 6: Custom prompts
IO.puts("\n=== Example 6: Custom Prompts ===\n")

{:ok, bullet_summary} =
  Document.generate_summary(doc,
    system_message: """
    Summarize the following content as a bulleted list of key points.
    Each bullet should be concise and capture one main idea.
    Use no more than 5 bullets.
    """
  )

IO.puts("Bullet Summary:\n#{bullet_summary.summary}\n")

# Example 7: Handling errors with fallback LLMs
IO.puts("\n=== Example 7: Fallback LLMs ===\n")

# Create a fallback LLM (would need proper configuration in real use)
# fallback_llm = ChatOpenAI.new!(%{model: "gpt-3.5-turbo", api_key: "..."})

# This would use the fallback if the primary LLM fails
# {:ok, summary} = Document.generate_summary(doc,
#   with_fallbacks: [fallback_llm]
# )

IO.puts("Fallback example skipped (requires additional LLM configuration)\n")

IO.puts("\n=== Examples Complete ===")
