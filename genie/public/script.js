// Mimic jquery:
const $ = selector => document.querySelector(selector);

// Upload:
function upload(status_id, file_id, post, callback) {
    url = '/upload'
    const statusEl = $(status_id);

    statusEl.style.color = "black";

    const file = $(file_id).files[0];
    if (!file) {
        statusEl.textContent = "No file selected!";
        return
    }
    const formData = new FormData();
    formData.append('type', post);
    formData.append('table', file);

    const xhr = new XMLHttpRequest();

    xhr.upload.onprogress = (e) => {
        if (e.lengthComputable) {
            const percent = Math.round((e.loaded / e.total) * 100);
            statusEl.textContent = `Uploading: ${percent}%`;
        }
    };

    xhr.onload = () => {
        callback()
        const data = JSON.parse(xhr.responseText);
        statusEl.textContent = data.message;
        statusEl.style.color = data.status == 1 ? "green" : "red";
    };

    xhr.open('POST', url);
    xhr.send(formData);
}

// Updating all:
async function update_status() {
    const response = await fetch('/query', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
    });
    const data = await response.json();
    orders_ready = data.orders_ready
    params_ready = data.params_ready
    if (orders_ready && params_ready) {
        $('#ddmpr_text').textContent = "Please download the Zones table:";
        $('#stats_text').textContent = "Please see the statistics for the SKUs:";
        $('#ddmrp_link').style.display = 'block';
        $('#stats_link').style.display = 'block';
        $('#ddmrp_link2').style.display = 'block';
        $('#stats_link2').style.display = 'block';
    } else {
        $('#ddmpr_text').textContent = "Please upload the sales table and parameters table first.";
        $('#stats_text').textContent = "Please upload the sales table and parameters table first.";
        $('#ddmrp_link').style.display = 'none';
        $('#stats_link').style.display = 'none';
        $('#ddmrp_link2').style.display = 'none';
        $('#stats_link2').style.display = 'none';
    }
    $('#orders_text').textContent = data.orders_text;
    $('#params_text').textContent = data.params_text;

// Second page:
    orders2_ready = data.orders2_ready
    ddmrp_ready = data.ddmrp_ready
    if (orders2_ready && ddmrp_ready) {
        $('#stats2_text').textContent = "Please see the simulation results for the SKUs:";
        $('#simulator_links').style.display = 'block';
    } else {
        $('#stats2_text').textContent = "Please upload the sales table and zones table first.";
        $('#simulator_links').style.display = 'none';
    }
    $('#orders2_text').textContent = data.orders2_text;
    $('#ddmrp_text').textContent = data.ddmrp_text;
// SKUs Assembly:
    $('#simulator_links').innerHTML = "";
    // Start from index 1 to skip PARAMS[0] as requested
    for (let i = 0; i < data.skus.length; i++) {
        const link = document.createElement("a");
        
        // This creates a URL like: page.html?data=value1
        link.href = `./simulator?sku=${encodeURIComponent(data.skus[i])}`;
        link.textContent = `${data.skus[i]}`;
        link.style.display = "block"; // Put each link on a new line
        
        $('#simulator_links').appendChild(link);
    }
}