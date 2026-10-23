import '@rainbow-me/rainbowkit/styles.css'
import { getDefaultConfig, RainbowKitProvider, darkTheme } from '@rainbow-me/rainbowkit'
import { WagmiProvider } from 'wagmi'
import { base } from 'wagmi/chains'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Presale } from './components/Presale'

const config = getDefaultConfig({
  appName: 'Seraph Presale',
  // Get a free project ID at https://cloud.walletconnect.com
  projectId: import.meta.env.VITE_WALLETCONNECT_PROJECT_ID || 'PLACEHOLDER_PROJECT_ID',
  chains: [base],
})

const queryClient = new QueryClient()

export default function App() {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider
          theme={darkTheme({
            accentColor: '#2f4cff',
            accentColorForeground: 'white',
            borderRadius: 'none',
            fontStack: 'system',
          })}
        >
          <Presale />
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  )
}
