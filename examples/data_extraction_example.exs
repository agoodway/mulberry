# Data Extraction Example
# This example demonstrates how to extract structured data from documents using Mulberry

# First, set up your environment variables:
# export OPENAI_API_KEY=your_key_here

alias Mulberry.Document
alias Mulberry.Document.WebPage

# Example 1: Extract structured data from text
text = """
John Smith is a 32-year-old software engineer at TechCorp in San Francisco.
He specializes in Elixir and has 8 years of experience.
Jane Doe, aged 28, works as a senior data scientist at DataCo in New York.
She has expertise in Python and machine learning with 5 years of experience.
"""

# Define the schema for the data we want to extract
person_schema = %{
  type: "object",
  properties: %{
    name: %{type: "string", description: "Full name of the person"},
    age: %{type: "number", description: "Age in years"},
    occupation: %{type: "string", description: "Job title"},
    company: %{type: "string", description: "Company name"},
    location: %{type: "string", description: "City or location"},
    skills: %{type: "array", items: %{type: "string"}, description: "Technical skills"},
    experience_years: %{type: "number", description: "Years of experience"}
  }
}

# Extract data using the Text module directly
{:ok, extracted_people} = Mulberry.Text.extract(text, schema: person_schema)

IO.puts("Extracted People Data:")
IO.inspect(extracted_people, pretty: true)

# Example 2: Extract data from a document
# Create a document (in practice, you'd load this from a URL or file)
doc = %WebPage{
  url: "https://example.com/team",
  markdown: text
}

# Use the Document protocol to extract data
{:ok, doc_with_data} = Document.transform(doc, :extract, schema: person_schema)

IO.puts("\nDocument with Extracted Data:")
IO.inspect(doc_with_data.extracted_data, pretty: true)

# Example 3: Extract different types of data - Products
product_text = """
Our store offers:
- MacBook Pro 16" for $2,499 with M3 Pro chip and 18GB RAM
- iPhone 15 Pro at $999 featuring titanium design and A17 Pro chip
- AirPods Pro (2nd gen) priced at $249 with active noise cancellation
"""

product_schema = %{
  type: "object",
  properties: %{
    product_name: %{type: "string"},
    price: %{type: "number", description: "Price in USD"},
    features: %{type: "array", items: %{type: "string"}}
  }
}

{:ok, products} = Mulberry.Text.extract(product_text, schema: product_schema)

IO.puts("\nExtracted Product Data:")
IO.inspect(products, pretty: true)

# Example 4: Extract data from a loaded web page
# In a real scenario, you would load the page first:
# {:ok, loaded_page} = Document.load(web_page)
# {:ok, page_with_data} = Document.transform(loaded_page, :extract, schema: schema)