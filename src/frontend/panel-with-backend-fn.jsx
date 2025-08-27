import React, { useEffect, useState } from 'react';
import ForgeReconciler from '@forge/react';
import { invoke } from '@forge/bridge';
import InvokeServicePanelComponent from "./InvokeServicePanelComponent";

const App = () => {
    const [data, setData] = useState(null);

    useEffect(() => {
        console.log("Invoking panel-invoke-resolver ...")

        /*
          Invoke a resolver from the backend Forge Function with the given key.
         */
        const fetchData = async () => {
            const res = await invoke('invoke-service-resolver');
            setData(res);
            console.log(`panel-invoke-resolver response: ${JSON.stringify(res, null, 2)}`)
        }

        fetchData()
    }, []);

    return (
        <InvokeServicePanelComponent data={data} />
    )
};

ForgeReconciler.render(
    <React.StrictMode>
        <App/>
    </React.StrictMode>
);
