# Genie stuff:
using Genie, Genie.Router, Genie.Renderer.Html, Genie.Requests, Genie.Renderer.Json, Genie.Responses
# HTTP (for serving downloads):
using HTTP
# Libraries used in code:
using XLSX, DataFrames, Dates, Statistics, Printf, Distributions, CategoricalArrays, Printf, CairoMakie

# Global state:
###############

struct TimedDataFrame
    df::DataFrame
    time::DateTime

    TimedDataFrame() = new(DataFrame(), DateTime(2000))
    TimedDataFrame(df) = new(df, Dates.now())
end

global_variables = Dict(
    "order_history" => TimedDataFrame(),
    "parameters" => TimedDataFrame(),
    "order_history2" => TimedDataFrame(),
    "simulator_ddmrp" => TimedDataFrame()
)

# Precomnputing:
################
const templates = Dict(
    "order_history" => (
        sheet_name = "Sheet1",
        date_fmt = dateformat"dd.mm.yyyy",
        rows = Dict(
            "Part Number"             => (CategoricalValue{String}, "sku" ),
            "Data"                    => (Date                    , "date"),
            "Sold Qty"                => (Float64                 , "qty" ),
            "Office Location"         => (CategoricalValue{String}, "loc" ),
            # Dropped columns:
            #"Part Name"              => 
            #"Invoice"                =>
            #"Invoice No to customer" =>
        ),
        def_values = Dict()
    ),
    "order_history2" => (
        sheet_name = "Sheet1",
        date_fmt = dateformat"dd.mm.yyyy",
        rows = Dict(
            "Part Number"             => (CategoricalValue{String}, "sku" ),
            "Data"                    => (Date                    , "date"),
            "Sold Qty"                => (Float64                 , "qty" ),
            "Office Location"         => (CategoricalValue{String}, "loc" ),
            # Dropped columns:
            #"Part Name"              => 
            #"Invoice"                =>
            #"Invoice No to customer" =>
        ),
        def_values = Dict()
    ),
    "parameters" => (
        sheet_name = "Sheet1", 
        rows = Dict(
            "Part Number"                 => (String , "sku"           ),
            "Synonym Part Number"         => (String , "sku_additional"),
            "Lead Time Supplier"          => (Int    , "lt"            ),
            "Minimum Order Supplier"      => (Float64, "moq"           ),
            "Lead Time Our Locations"     => (Int    , "lt_inner"      ),
            "Minimum Order Our Locations" => (Float64, "moq_inner"     ),
            "Service Level"               => (Float64, "sl"            ),
            "Order Cycle Supplier"        => (Int    , "oc"            ),
            "Order Cycle Our Locations"   => (Int    , "oc_inner"      ),
            "Red Safety Factor"           => (Float64, "red_safety"    ),
        ),
        def_values = Dict(
            "Synonym Part Number"         => "",
            "Order Cycle Supplier"        => 0 ,
            "Order Cycle Our Locations"   => 0 ,
        )
    ),
    "order_generator" => (
        sheet_name = "Sheet1", 
        rows = Dict(
            "Part Number"    => (String , "sku"    ),
            "Yellow"         => (Float64, "yellow"  ),
            "Green"          => (Float64, "green"  ),
            "Order Position" => (Float64, "on_hand"),
        ),
        def_values = Dict(
            "Yellow"         => -1,
            "Order Position" => -1,
        )
    ),
    "simulator_ddmrp" => (
        sheet_name = "Sheet1", 
        rows = Dict(
            "Part Number"         => (String , "sku"           ),
            "Synonym Part Number" => (String , "sku_additional"),
            "Office Location"     => (String , "loc"           ),
            "Lead Time"           => (Int    , "lt_inner"      ),
            "Order Cycle"         => (Int    , "oc"            ),
            "Minimum Order"       => (Float64, "moq"           ),
            "Yellow"              => (Float64, "y"             ),
            "Green"               => (Float64, "g"             ),
            "Red"                 => (Float64, "r"             ),
            "Initial Stock"       => (Float64, "init"          ),
        ),
        def_values = Dict(
            "Synonym Part Number" => "",
            "Red"                 => 0.0
        )
    ),
    "stock_orders" => (
        sheet_name = "",
        date_fmt = "",
        rows = Dict(
            "Part No"        => (String , "sku"    ),
            "Delivered Qty"  => (Float64, "qty"    ),
            "Order Date"     => (Date   , "ordered"),
            #"ETA*"           => (Date   , "arrival"),
        ),
        def_values = Dict(
            #"ETA*"           => Date(2000),
        )
    )
)

function excel_to_df(payload::Union{String, IO}, template)
    function robust_transform(col_data, target_type)
        # 1. Handle Categorical Request
        if target_type == CategoricalValue{String}
            return categorical(col_data)
        end
        if target_type == Date
            if template.date_fmt != ""
                return Date.(col_data, template.date_fmt)
            end
            return Date.(col_data)
        end
        target_type.(col_data)
    end

    xf = XLSX.readxlsx(payload)
    df = template.sheet_name == "" ? vcat([DataFrame(XLSX.gettable(xf[name])) for name in XLSX.sheetnames(xf)]...) : DataFrame(XLSX.gettable(xf[template.sheet_name]))
    
    for (key, def_value) in template.def_values
        df[!, key] = coalesce.(df[!, key], def_value)
    end

    def_dic = template.rows
    df = select!(
        df,
        [
            col => (x -> robust_transform(x, def_dic[col][1])) => def_dic[col][2] 
            for col in names(df) if haskey(def_dic, col)
        ]...
    )

    df
end

# Web:
######

# Everything is contained in this file (and other supplementary files)
route("/") do
  serve_static_file("index.html")
end

# Any query is processed here:
route("/query", method = POST) do
    params_text = "No parameters table is uploaded."
    if global_variables["parameters"].time != DateTime(2000)
        params_text = @sprintf(
            "Using table uploaded on %s. Containing %d rows.",
            Dates.format(global_variables["parameters"].time, "dd u yyyy HH:MM:SS"),
            size(global_variables["parameters"].df, 1)
        )
    end

    orders_text = "No order history table is uploaded."
    if global_variables["order_history"].time != DateTime(2000)
        skus = String.(levels(global_variables["order_history"].df[1, "sku"].pool))
        dates = extrema(global_variables["order_history"].df[:, "date"])
        locs = String.(levels(global_variables["order_history"].df[1, "loc"].pool))
        orders_text = @sprintf(
            "Using table uploaded on %s. Covering time period from %s to %s with SKUs = %s, locations = %s.",
            Dates.format(global_variables["order_history"].time, "dd u yyyy HH:MM:SS"),
            Dates.format(dates[1], "dd u yyyy"),
            Dates.format(dates[2], "dd u yyyy"),
            repr(skus),
            repr(locs)
        )
    end

    orders2_text = "No order history table is uploaded."
    if global_variables["order_history2"].time != DateTime(2000)
        skus = String.(levels(global_variables["order_history2"].df[1, "sku"].pool))
        dates = extrema(global_variables["order_history2"].df[:, "date"])
        locs = String.(levels(global_variables["order_history2"].df[1, "loc"].pool))
        orders2_text = @sprintf(
            "Using table uploaded on %s. Covering time period from %s to %s with SKUs = %s, locations = %s.",
            Dates.format(global_variables["order_history2"].time, "dd u yyyy HH:MM:SS"),
            Dates.format(dates[1], "dd u yyyy"),
            Dates.format(dates[2], "dd u yyyy"),
            repr(skus),
            repr(locs)
        )
    end

    ddmrp_text = "No zones table is uploaded."
    if global_variables["simulator_ddmrp"].time != DateTime(2000)
        ddmrp_text = @sprintf(
            "Using table uploaded on %s. Containing %d rows.",
            Dates.format(global_variables["simulator_ddmrp"].time, "dd u yyyy HH:MM:SS"),
            size(global_variables["simulator_ddmrp"].df, 1)
        )
    end

    json(Dict(
        "params_ready" => global_variables["order_history"].time != DateTime(2000),
        "orders_ready" => global_variables["parameters"   ].time != DateTime(2000),
        "params_text"  => params_text,
        "orders_text"  => orders_text,
        # Second page:
        "orders2_ready" => global_variables["order_history2" ].time != DateTime(2000),
        "ddmrp_ready"   => global_variables["simulator_ddmrp"].time != DateTime(2000),
        "orders2_text"  => orders2_text,
        "ddmrp_text"    => ddmrp_text,
        "skus"          => global_variables["simulator_ddmrp"].time == DateTime(2000) ? [] : unique(global_variables["simulator_ddmrp"].df[!, "sku"])
    ))
end

# Uploading (and preparing table)
route("/upload", method = POST) do
    table_name = postpayload(:type, "missing")
    if table_name == "missing" || !(table_name in keys(templates))
        return json(Dict("status" => 0, "message" => "Incorrect upload type."))
    end
    df = try 
        excel_to_df(IOBuffer(filespayload()["table"].data), templates[table_name])
    catch e
        return json(Dict("status" => 0, "message" => "Error while reading the table"))
    end 
    if size(df, 1) == 0
        return json(Dict("status" => 0, "message" => "Loaded table has no correct rows"))
    end
    if size(df, 2) != length(keys(templates[table_name].rows))
        return json(Dict("status" => 0, "message" => "Some columns of the input table are damaged"))
    end
    # Only now update the table:
    global_variables[table_name] = TimedDataFrame(df)
    return json(Dict("status" => 1, "message" => "Updated the table successfully"))
end

# New statistics page:
# todo

# New download ddmrp page:
# todo

route("/order_generator", method = POST) do
    # upload the table
    df = try 
        excel_to_df(IOBuffer(filespayload()["table"].data), templates["order_generator"])
    catch e
        return repr("Error while reading the table!")
    end
    out = []
    # Go through:
    for row in eachrow(df)
        if row["on_hand"] == -1
            continue
        end
        if row["yellow"] != -1 && row["on_hand"] > row["yellow"]
            continue
        end
        quantity = Int(ceil(row["green"] - row["on_hand"]))
        if quantity <= 0
            continue
        end
        push!(out, (row["sku"], quantity))
    end

    if length(out) == 0
        return repr("No order was generated!")
    end
    # Generate csv and send:
    str = ""
    for (x, y) in out
        str = str * string(x) * ";" * string(y) * '\n'
    end

    return HTTP.Response(200, 
        [
            "Content-Type" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "Content-Disposition" => "attachment; filename=\"order.csv\""
        ], 
        body = str
    )
end

route("/erase", method = POST) do
    global_variables["order_history"] = TimedDataFrame()
    global_variables["parameters"]    = TimedDataFrame()
    return json("")
end

route("/erase2", method = POST) do
    global_variables["order_history2"] = TimedDataFrame()
    global_variables["simulator_ddmrp"]    = TimedDataFrame()
    return json("")
end

global_variables = Dict(
    "order_history" => TimedDataFrame(),
    "parameters" => TimedDataFrame(),
    "order_history2" => TimedDataFrame(),
    "simulator_ddmrp" => TimedDataFrame()
)

route("/simulator") do
    if global_variables["order_history2"].time == DateTime(2000) || global_variables["simulator_ddmrp"].time == DateTime(2000)
        return repr("Upload the tables first")
    end
    sku = query(:sku, "")
    if sku == ""
        return repr("Error in SKU parsing.")
    end
    plot_html = try
        [repr(MIME"text/html"(), plt) for plt in simulator_from_dfs(global_variables["order_history2"].df, global_variables["simulator_ddmrp"].df, sku)]
    catch
        return repr("Error in simulation with given SKU = " * sku)
    end

    plot_html = join(plot_html)

    html(
        """
        <!DOCTYPE html>
        <html>
        <head><title>Zones calculator</title></head>
        <body>
            $(plot_html)
        </body>
        </html>
        """
    )
end

# OLD BAD CODE:
###############

route("/statistics") do
    if global_variables["order_history"].time == DateTime(2000) || global_variables["parameters"].time == DateTime(2000)
        return repr("Upload the tables first")
    end

    plot_html = [repr(MIME"text/html"(), plt) for plt in plots_from_dfs(global_variables["order_history"].df, global_variables["parameters"].df)]
    if length(plot_html) == 0
        return repr("No statistics were generated. Check if SKUs are present in parameter table!")
    end

    plot_html = join(plot_html)

    html(
        """
        <!DOCTYPE html>
        <html>
        <head><title>Zones calculator</title></head>
        <body>
            $(plot_html)
        </body>
        </html>
        """
    )
end

route("/statistics_sofia") do
    if global_variables["order_history"].time == DateTime(2000) || global_variables["parameters"].time == DateTime(2000)
        return repr("Upload the tables first")
    end

    plot_html = [repr(MIME"text/html"(), plt) for plt in plots_from_dfs(global_variables["order_history"].df, global_variables["parameters"].df; only_sofia = true)]
    if length(plot_html) == 0
        return repr("No statistics were generated. Check if SKUs are present in parameter table!")
    end

    plot_html = join(plot_html)

    html(
        """
        <!DOCTYPE html>
        <html>
        <head><title>Zones calculator</title></head>
        <body>
            $(plot_html)
        </body>
        </html>
        """
    )
end

route("/download_zones") do
    if global_variables["order_history"].time == DateTime(2000) || global_variables["parameters"].time == DateTime(2000)
        return repr("Upload the tables first")
    end

    df = ddmrp_df_from_dfs(global_variables["order_history"].df, global_variables["parameters"].df)

    if size(df, 1) == 0
        return repr("No zones were generated. Check if SKUs are present in parameter table!")
    end
    
    io = IOBuffer()
    XLSX.writetable(io, "Sheet1" => df)

    seekstart(io)
    return HTTP.Response(200, 
        [
            "Content-Type" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "Content-Disposition" => "attachment; filename=\"report.xlsx\""
        ], 
        body = take!(io)
    )
end

route("/download_zones_sofia") do
    if global_variables["order_history"].time == DateTime(2000) || global_variables["parameters"].time == DateTime(2000)
        return repr("Upload the tables first")
    end

    df = ddmrp_df_from_dfs(global_variables["order_history"].df, global_variables["parameters"].df; only_sofia = true)

    if size(df, 1) == 0
        return repr("No zones were generated. Check if SKUs are present in parameter table!")
    end
    
    io = IOBuffer()
    XLSX.writetable(io, "Sheet1" => df)

    seekstart(io)
    return HTTP.Response(200, 
        [
            "Content-Type" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "Content-Disposition" => "attachment; filename=\"report.xlsx\""
        ], 
        body = take!(io)
    )
end
