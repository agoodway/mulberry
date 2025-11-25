defmodule DataForSEO.Schemas.GoogleEvent do
  @moduledoc """
  Schema for a Google Event item returned from DataForSEO API.

  Represents an individual event with details like title, date, location, and URLs.
  """

  @type t :: %__MODULE__{
          type: String.t(),
          title: String.t() | nil,
          description: String.t() | nil,
          url: String.t() | nil,
          date: String.t() | nil,
          event_dates: event_dates() | nil,
          location: location() | nil,
          tickets_url: String.t() | nil,
          more_info_url: String.t() | nil,
          information_and_tickets: [ticket_info()] | nil,
          image_url: String.t() | nil,
          position: integer() | nil,
          xpath: String.t() | nil
        }

  @type location :: %{
          name: String.t() | nil,
          address: String.t() | nil,
          url: String.t() | nil,
          cid: String.t() | nil,
          feature_id: String.t() | nil
        }

  @type event_dates :: %{
          start_datetime: String.t() | nil,
          end_datetime: String.t() | nil,
          displayed_dates: String.t() | nil
        }

  @type ticket_info :: %{
          type: String.t() | nil,
          title: String.t() | nil,
          description: String.t() | nil,
          url: String.t() | nil,
          domain: String.t() | nil
        }

  defstruct [
    :type,
    :title,
    :description,
    :url,
    :date,
    :event_dates,
    :location,
    :tickets_url,
    :more_info_url,
    :information_and_tickets,
    :image_url,
    :position,
    :xpath
  ]

  @doc """
  Creates a new GoogleEvent struct from a map of attributes.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    struct(__MODULE__, attrs)
  end
end
